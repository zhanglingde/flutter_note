import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../utils/markdown_auto_converter.dart';
import '../services/image_storage_service.dart';

/// 富文本编辑器组件
class RichTextEditor extends StatefulWidget {
  final String initialContent;
  final Function(String) onContentChanged;
  final String noteId;

  const RichTextEditor({
    super.key,
    required this.initialContent,
    required this.onContentChanged,
    required this.noteId,
  });

  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  late QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isInitialized = false;

  final ImageStorageService _imageService = ImageStorageService();

  /// Markdown 自动转换器
  MarkdownAutoConverter? _markdownConverter;

  /// 是否启用 Markdown 自动转换
  bool _markdownEnabled = true;

  /// 切换 Markdown 自动转换
  void toggleMarkdown() {
    setState(() {
      _markdownEnabled = !_markdownEnabled;
      if (_markdownConverter != null) {
        _markdownConverter!.enabled = _markdownEnabled;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _initializeController();
  }

  void _initializeController() {
    try {
      if (widget.initialContent.isNotEmpty) {
        final document = Document.fromJson(
          jsonDecode(widget.initialContent) as List<dynamic>,
        );
        _controller = QuillController(
          document: document,
          selection: TextSelection.collapsed(offset: document.length - 1),
        );
      } else {
        _controller = QuillController.basic();
      }
    } catch (e) {
      _controller = QuillController.basic();
    }

    _controller.addListener(_onContentChanged);
    _isInitialized = true;

    _markdownConverter = MarkdownAutoConverter(
      controller: _controller,
      enabled: _markdownEnabled,
    );
  }

  void _onContentChanged() {
    if (!_isInitialized) return;

    _detectMarkdownTrigger();

    final json = jsonEncode(_controller.document.toDelta().toJson());
    widget.onContentChanged(json);
  }

  /// 检测 Markdown 触发条件
  void _detectMarkdownTrigger() {
    if (_markdownConverter == null || !_markdownEnabled) return;

    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;

    final document = _controller.document;
    final plainText = document.toPlainText();

    if (selection.baseOffset <= 0 || selection.baseOffset > plainText.length) {
      return;
    }

    final char = plainText[selection.baseOffset - 1];

    if (char == ' ') {
      _markdownConverter!.handleTextChange('space');
    } else if (char == '\n') {
      _markdownConverter!.handleTextChange('enter');
    } else if (char == '*' || char == '_' || char == '`' || char == '~') {
      _markdownConverter!.handleTextChange('inline');
    }
  }

  /// 全局键盘事件：在 Quill 处理之前拦截 Ctrl+V
  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!_focusNode.hasFocus) return false;

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed) {
      _handlePaste();
      return true; // 消费事件，阻止 Quill 默认粘贴
    }
    return false;
  }

  /// 统一粘贴处理：优先图片，其次文本
  Future<void> _handlePaste() async {
    // 1. 检查剪贴板是否有图片
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final reader = await clipboard.read();
        final formats = reader.getFormats([Formats.png, Formats.jpeg]);
        if (formats.isNotEmpty) {
          final format = formats.first as FileFormat;
          final ext = format == Formats.jpeg ? 'jpg' : 'png';
          final bytes = await _readClipboardFile(reader, format);
          if (bytes != null) {
            await _insertImage(bytes, extension: ext);
            return;
          }
        }
      }
    } catch (_) {}

    // 2. 没有图片，粘贴文本
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      final index = _controller.selection.baseOffset;
      final length = _controller.selection.extentOffset - index;
      _controller.replaceText(
        index,
        length,
        data.text!,
        TextSelection.collapsed(offset: index + data.text!.length),
      );
    }
  }

  /// 从剪贴板粘贴图片
  Future<void> _pasteImageFromClipboard() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return;

      final reader = await clipboard.read();

      // 检查可用的图片格式
      final availableFormats = reader.getFormats([
        Formats.png,
        Formats.jpeg,
      ]);

      if (availableFormats.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('剪贴板中没有图片')),
          );
        }
        return;
      }

      final format = availableFormats.first as FileFormat;
      final extension = format == Formats.jpeg ? 'jpg' : 'png';

      final bytes = await _readClipboardFile(reader, format);
      if (bytes != null) {
        await _insertImage(bytes, extension: extension);
      }
    } catch (e) {
      debugPrint('粘贴图片失败: $e');
    }
  }

  /// 从剪贴板读取文件格式数据
  Future<Uint8List?> _readClipboardFile(
    ClipboardReader reader,
    FileFormat format,
  ) async {
    final completer = Completer<Uint8List?>();

    reader.getFile(format, (file) async {
      try {
        final all = await file.readAll();
        completer.complete(all);
      } catch (e) {
        completer.completeError(e);
      }
    }, onError: (e) {
      completer.completeError(e);
    });

    return completer.future;
  }

  /// 从文件选择器选择图片
  Future<void> _pickImageFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        await _insertImage(bytes);
      }
    } catch (e) {
      debugPrint('选择图片失败: $e');
    }
  }

  /// 保存图片并插入到编辑器
  Future<void> _insertImage(Uint8List bytes, {String extension = 'png'}) async {
    final filePath = await _imageService.saveImage(
      bytes,
      widget.noteId,
      extension: extension,
    );

    final imageData = jsonEncode({
      'source': filePath,
      'width': 400,
    });

    final index = _controller.selection.baseOffset;
    _controller.replaceText(
      index,
      0,
      BlockEmbed('image', imageData),
      null,
    );
  }

  @override
  void didUpdateWidget(RichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _controller.removeListener(_onContentChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 构建自定义工具栏
  Widget _buildToolbar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.undo, size: 20),
              onPressed: _controller.hasUndo ? _controller.undo : null,
              tooltip: '撤销',
            ),
            IconButton(
              icon: const Icon(Icons.redo, size: 20),
              onPressed: _controller.hasRedo ? _controller.redo : null,
              tooltip: '重做',
            ),
            _toolbarDivider(),
            _buildParagraphMenu(),
            _toolbarDivider(),
            _buildFormatMenu(),
            _toolbarDivider(),
            // 粘贴图片按钮
            IconButton(
              icon: const Icon(Icons.content_paste, size: 20),
              onPressed: _pasteImageFromClipboard,
              tooltip: '粘贴图片',
            ),
            // 选择图片按钮
            IconButton(
              icon: const Icon(Icons.image_outlined, size: 20),
              onPressed: _pickImageFromFile,
              tooltip: '选择图片',
            ),
            _toolbarDivider(),
            Tooltip(
              message: _markdownEnabled
                  ? 'Markdown 自动转换：开'
                  : 'Markdown 自动转换：关',
              child: IconButton(
                icon: Icon(
                  Icons.code,
                  size: 20,
                  color: _markdownEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                onPressed: toggleMarkdown,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: VerticalDivider(width: 1, indent: 12, endIndent: 12),
    );
  }

  /// 段落菜单
  Widget _buildParagraphMenu() {
    return PopupMenuButton<String>(
      icon: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.format_shapes, size: 20),
          SizedBox(width: 2),
          Text('段落', style: TextStyle(fontSize: 12)),
          Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
      tooltip: '段落',
      onSelected: (value) {
        final attr = switch (value) {
          'h1' => Attribute.h1,
          'h2' => Attribute.h2,
          'h3' => Attribute.h3,
          'ul' => Attribute.ul,
          'ol' => Attribute.ol,
          'codeBlock' => Attribute.codeBlock,
          'checked' => Attribute.checked,
          'blockquote' => Attribute.blockQuote,
          _ => null,
        };
        if (attr != null) {
          _controller.formatSelection(attr);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'h1', child: Text('标题 1')),
        const PopupMenuItem(value: 'h2', child: Text('标题 2')),
        const PopupMenuItem(value: 'h3', child: Text('标题 3')),
        const PopupMenuItem(value: 'ul', child: Text('无序列表')),
        const PopupMenuItem(value: 'ol', child: Text('有序列表')),
        const PopupMenuItem(value: 'checked', child: Text('待办')),
        const PopupMenuItem(value: 'codeBlock', child: Text('代码块')),
        const PopupMenuItem(value: 'blockquote', child: Text('引用')),
      ],
    );
  }

  /// 格式菜单
  Widget _buildFormatMenu() {
    return PopupMenuButton<String>(
      icon: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.text_format, size: 20),
          SizedBox(width: 2),
          Text('格式', style: TextStyle(fontSize: 12)),
          Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
      tooltip: '格式',
      onSelected: (value) {
        final attr = switch (value) {
          'bold' => Attribute.bold,
          'italic' => Attribute.italic,
          'underline' => Attribute.underline,
          'strikeThrough' => Attribute.strikeThrough,
          'inlineCode' => Attribute.inlineCode,
          _ => null,
        };
        if (attr != null) {
          _controller.formatSelection(attr);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'bold', child: Text('加粗')),
        const PopupMenuItem(value: 'italic', child: Text('斜体')),
        const PopupMenuItem(value: 'underline', child: Text('下划线')),
        const PopupMenuItem(value: 'strikeThrough', child: Text('删除线')),
        const PopupMenuItem(value: 'inlineCode', child: Text('行内代码')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: QuillEditor(
              controller: _controller,
              focusNode: _focusNode,
              scrollController: _scrollController,
              config: QuillEditorConfig(
                padding: const EdgeInsets.only(left: 100, top: 16, right: 100, bottom: 16),
                placeholder: '开始输入...',
                autoFocus: false,
                embedBuilders: [
                  _ImageEmbedBuilder(controller: _controller),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 图片嵌入渲染器
class _ImageEmbedBuilder extends EmbedBuilder {
  final QuillController controller;

  _ImageEmbedBuilder({required this.controller});

  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final rawData = embedContext.node.value.data as String;

    // 兼容旧格式（纯路径）和 JSON 格式
    String source;
    double width;
    try {
      final json = jsonDecode(rawData) as Map<String, dynamic>;
      source = json['source'] as String;
      width = (json['width'] as num?)?.toDouble() ?? 400.0;
    } catch (_) {
      source = rawData;
      width = 400.0;
    }

    return _ResizableImage(
      source: source,
      initialWidth: width,
      onWidthChanged: (newWidth) {
        final newData = jsonEncode({
          'source': source,
          'width': newWidth.round(),
        });
        final offset = _findEmbedOffset(controller, embedContext.node);
        if (offset >= 0) {
          controller.replaceText(
            offset,
            1,
            BlockEmbed('image', newData),
            TextSelection.collapsed(offset: offset + 1),
          );
        }
      },
      onDelete: () {
        final offset = _findEmbedOffset(controller, embedContext.node);
        if (offset >= 0) {
          controller.replaceText(offset, 1, '', null);
        }
      },
    );
  }

  /// 在文档中查找 embed 节点的偏移位置
  int _findEmbedOffset(QuillController controller, Node targetNode) {
    return targetNode.documentOffset;
  }
}

/// 可调整大小的图片组件
class _ResizableImage extends StatefulWidget {
  final String source;
  final double initialWidth;
  final ValueChanged<double> onWidthChanged;
  final VoidCallback onDelete;

  const _ResizableImage({
    required this.source,
    required this.initialWidth,
    required this.onWidthChanged,
    required this.onDelete,
  });

  @override
  State<_ResizableImage> createState() => _ResizableImageState();
}

class _ResizableImageState extends State<_ResizableImage> {
  late double _width;
  bool _isSelected = false;
  double? _originalWidth;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
    _resolveImageSize();
  }

  bool get _isNetworkUrl =>
      widget.source.startsWith('http://') || widget.source.startsWith('https://');

  void _resolveImageSize() {
    final ImageProvider provider =
        _isNetworkUrl ? NetworkImage(widget.source) : FileImage(File(widget.source));
    provider.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) {
          setState(() {
            _originalWidth = info.image.width.toDouble();
          });
        }
      }),
    );
  }

  Widget _buildImage() {
    final errorWidget = Container(
      width: _width,
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade200,
      child: const Row(
        children: [
          Icon(Icons.broken_image, size: 16),
          SizedBox(width: 4),
          Text('图片无法加载', style: TextStyle(fontSize: 12)),
        ],
      ),
    );

    if (_isNetworkUrl) {
      return Image.network(
        widget.source,
        width: _width,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => errorWidget,
      );
    }
    return Image.file(
      File(widget.source),
      width: _width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => errorWidget,
    );
  }

  @override
  void didUpdateWidget(covariant _ResizableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWidth != widget.initialWidth) {
      _width = widget.initialWidth;
    }
  }

  void _showContextMenu(TapDownDetails details) {
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(details.globalPosition);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('复制图片')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'small', child: Text('小 (200px)')),
        const PopupMenuItem(value: 'medium', child: Text('中 (400px)')),
        const PopupMenuItem(value: 'large', child: Text('大 (600px)')),
        const PopupMenuItem(value: 'original', child: Text('原始大小')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text('删除图片', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'copy':
          _copyImage();
          break;
        case 'small':
          _updateWidth(200);
          break;
        case 'medium':
          _updateWidth(400);
          break;
        case 'large':
          _updateWidth(600);
          break;
        case 'original':
          _updateWidth(_originalWidth ?? 800);
          break;
        case 'delete':
          widget.onDelete();
          break;
      }
    });
  }

  void _updateWidth(double newWidth, {bool saveToDocument = true}) {
    setState(() => _width = newWidth);
    if (saveToDocument) {
      widget.onWidthChanged(newWidth);
    }
  }

  /// 显示原图预览浮层
  void _showImagePreview() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _ImagePreviewOverlay(source: widget.source),
      ),
    );
  }

  /// 复制图片到剪贴板
  Future<void> _copyImage() async {
    try {
      if (_isNetworkUrl) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('网络图片暂不支持复制')),
          );
        }
        return;
      }
      final file = File(widget.source);
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return;
      final item = DataWriterItem();
      item.add(Formats.png(bytes));
      await clipboard.write([item]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片已复制到剪贴板')),
        );
      }
    } catch (e) {
      debugPrint('复制图片失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
      onTapDown: (_) => setState(() => _isSelected = true),
      onTap: () { if (!_isDragging) _showImagePreview(); },
      onSecondaryTapDown: _showContextMenu,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isSelected = true),
        onExit: (_) => setState(() => _isSelected = false),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: _isSelected
                ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _buildImage(),
              ),
              // 右下角拖拽调整大小手柄
              if (_isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      _isDragging = true;
                    },
                    onPointerMove: (event) {
                      if (!_isDragging) return;
                      final maxWidth = _originalWidth ?? 1200.0;
                      final newWidth = (_width + event.delta.dx).clamp(100.0, maxWidth);
                      _updateWidth(newWidth, saveToDocument: false);
                    },
                    onPointerUp: (_) {
                      if (_isDragging) {
                        _isDragging = false;
                        widget.onWidthChanged(_width);
                      }
                    },
                    onPointerCancel: (_) {
                      if (_isDragging) {
                        _isDragging = false;
                        widget.onWidthChanged(_width);
                      }
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1,
                        ),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(4),
                        ),
                      ),
                      child: Icon(
                        Icons.zoom_out_map,
                        size: 10,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// 图片原图预览浮层（支持滚轮缩放、拖拽平移）
class _ImagePreviewOverlay extends StatefulWidget {
  final String source;
  const _ImagePreviewOverlay({required this.source});

  @override
  State<_ImagePreviewOverlay> createState() => _ImagePreviewOverlayState();
}

class _ImagePreviewOverlayState extends State<_ImagePreviewOverlay> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;

  bool get _isNetworkUrl =>
      widget.source.startsWith('http://') || widget.source.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            setState(() {
              final zoomDelta = -event.scrollDelta.dy / 300;
              _scale = (_scale * (1 + zoomDelta)).clamp(0.5, 8.0);
            });
          }
        },
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          onDoubleTap: () => Navigator.of(context).pop(),
          onScaleStart: (_) => _baseScale = _scale,
          onScaleUpdate: (details) {
            setState(() {
              _scale = (_baseScale * details.scale).clamp(0.5, 8.0);
              _offset += details.focalPointDelta;
            });
          },
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(context).pop();
              }
            },
            child: Container(  // 图片背景不透明度
              color: Colors.black.withValues(alpha: 0.05),
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: Transform.translate(
                  offset: _offset,
                  child: Transform.scale(
                    scale: _scale,
                    child: Transform.scale(
                    scale: _scale,
                    child: _isNetworkUrl
                        ? Image.network(widget.source, fit: BoxFit.contain)
                        : Image.file(File(widget.source), fit: BoxFit.contain),
                  ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
