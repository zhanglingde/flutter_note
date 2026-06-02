import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:file_picker/file_picker.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:highlight/languages/all.dart' as languages;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'dart:convert';
import '../utils/markdown_auto_converter.dart';
import '../utils/cn_en_formatter.dart';
import '../services/image_storage_service.dart';
import 'outline_sidebar.dart';

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

  /// 代码块语言映射：Block 的第一个 Line 偏移量 -> 语言
  final Map<int, String> _codeBlockLanguages = {};

  /// 编辑器水平内边距
  static const _editorHorizontalPadding = 100.0;

  /// 编辑器内容区域实际宽度（由 LayoutBuilder 更新）
  double _editorContentWidth = 0;

  /// 语言标签的 GlobalKey，用于点击检测
  final Map<int, GlobalKey> _langLabelKeys = {};
  final Map<int, GlobalKey> _copyButtonKeys = {};

  /// 用于检测 header 区域的 tap
  Offset? _headerPointerDown;

  /// Markdown 自动转换器
  MarkdownAutoConverter? _markdownConverter;

  /// 是否显示大纲
  bool _showOutline = false;

  /// 大纲面板宽度
  double _outlineWidth = 240;

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
          selection: const TextSelection.collapsed(offset: 0),
          config: QuillControllerConfig(
            clipboardConfig: QuillClipboardConfig(
              onClipboardPaste: _onClipboardPaste,
            ),
          ),
        );
        // 从已保存的文档中恢复代码块语言信息
        _loadCodeBlockLanguages();
      } else {
        _controller = QuillController.basic(
          config: QuillControllerConfig(
            clipboardConfig: QuillClipboardConfig(
              onClipboardPaste: _onClipboardPaste,
            ),
          ),
        );
      }
    } catch (e) {
      _controller = QuillController.basic(
        config: QuillControllerConfig(
          clipboardConfig: QuillClipboardConfig(
            onClipboardPaste: _onClipboardPaste,
          ),
        ),
      );
    }

    _controller.addListener(_onContentChanged);
    _isInitialized = true;

    _markdownConverter = MarkdownAutoConverter(
      controller: _controller,
      enabled: true,
      onCodeBlockCreated: (offset, lang) {
        _codeBlockLanguages[offset] = lang;
        // 同时写入 Delta 持久化
        _persistCodeBlockLang(offset, lang);
      },
    );
  }

  /// 从已保存的文档 Delta 中恢复代码块语言信息
  void _loadCodeBlockLanguages() {
    _codeBlockLanguages.clear();
    for (final node in _controller.document.root.children) {
      if (node is Block) {
        final attrs = node.style.attributes;
        if (attrs.containsKey(Attribute.codeBlock.key)) {
          final firstLine = node.first;
          if (firstLine is! Line) continue;
          final blockOffset = firstLine.documentOffset;
          if (blockOffset < 0) continue;

          String? lang;

          // 1. 检查 Block 样式
          final blockLangAttr = attrs['code-block-lang'];
          if (blockLangAttr != null && blockLangAttr.value != null) {
            lang = blockLangAttr.value.toString();
          }

          // 2. 检查 Line 样式（\n 字符上的属性存储在 Line 级别）
          if (lang == null) {
            final lineLangAttr = firstLine.style.attributes['code-block-lang'];
            if (lineLangAttr != null && lineLangAttr.value != null) {
              lang = lineLangAttr.value.toString();
            }
          }

          // 3. 回退：遍历第一行所有 Leaf 节点查找属性
          if (lang == null) {
            for (final child in firstLine.children) {
              if (child is Leaf) {
                final leafAttr = child.style.attributes['code-block-lang'];
                if (leafAttr != null && leafAttr.value != null) {
                  lang = leafAttr.value.toString();
                  break;
                }
              }
            }
          }

          if (lang != null) {
            _codeBlockLanguages[blockOffset] = lang;
          }
        }
      }
    }
  }

  /// 将代码块语言写入 Delta 属性（持久化）
  /// 写入到第一行末尾 \n 字符上，与 code-block 属性共存
  void _persistCodeBlockLang(int blockOffset, String lang) {
    try {
      final block = _findBlockAtOffset(blockOffset);
      if (block == null) return;
      final firstLine = block.first;
      if (firstLine is! Line) return;

      // firstLine.length 包含 \n，所以 \n 的偏移 = blockOffset + firstLine.length - 1
      final nlOffset = blockOffset + firstLine.length - 1;
      final delta = Delta()
        ..retain(nlOffset)
        ..retain(1, {'code-block-lang': lang});
      _controller.compose(
        delta,
        _controller.selection,
        ChangeSource.local,
      );
    } catch (e) {
      debugPrint('persistCodeBlockLang failed: $e');
    }
  }

  /// 根据偏移量查找 Block 节点
  Block? _findBlockAtOffset(int offset) {
    for (final node in _controller.document.root.children) {
      if (node is Block) {
        final start = node.documentOffset;
        final end = start + node.length;
        if (offset >= start && offset <= end) {
          return node;
        }
      }
    }
    return null;
  }

  void _onContentChanged() {
    if (!_isInitialized) return;

    _detectMarkdownTrigger();

    final json = jsonEncode(_controller.document.toDelta().toJson());
    widget.onContentChanged(json);
  }

  /// 检测 Markdown 触发条件
  void _detectMarkdownTrigger() {
    if (_markdownConverter == null) return;

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

  /// 自定义粘贴回调：处理图片粘贴和代码块内纯文本粘贴
  Future<bool> _onClipboardPaste() async {
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
            return true;
          }
        }
      }
    } catch (_) {}

    // 2. 代码块内：只粘贴纯文本（避免 HTML 格式破坏代码块）
    if (_isCursorInCodeBlock()) {
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
      return true;
    }

    // 3. 非代码块：让 Quill 处理（支持富文本粘贴）
    return false;
  }

  /// 检查当前光标是否在代码块内
  bool _isCursorInCodeBlock() {
    final offset = _controller.selection.baseOffset;
    if (offset < 0) return false;
    for (final node in _controller.document.root.children) {
      if (node is Block) {
        final start = node.documentOffset;
        final end = start + node.length;
        if (offset >= start && offset < end) {
          return node.style.attributes.containsKey(Attribute.codeBlock.key);
        }
      }
    }
    return false;
  }

  /// 全局键盘事件：拦截代码块内 Ctrl+A 实现渐进式全选
  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!_focusNode.hasFocus) return false;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyA &&
        HardwareKeyboard.instance.isControlPressed) {
      return _handleSelectAll();
    }
    return false;
  }

  /// 渐进式全选：代码块内先选代码块，再按一次全选文档
  bool _handleSelectAll() {
    final selection = _controller.selection;
    if (!selection.isValid) return false;

    final offset = selection.baseOffset;

    // 查找包含选区起点的代码块
    for (final node in _controller.document.root.children) {
      if (node is Block) {
        final start = node.documentOffset;
        final end = start + node.length;
        if (offset >= start && offset < end &&
            node.style.attributes.containsKey(Attribute.codeBlock.key)) {
          // 已选中整个代码块 → 放行，让 Quill 全选文档
          if (selection.start <= start &&
              selection.end >= end - 1) {
            return false;
          }
          // 选中代码块
          _controller.updateSelection(
            TextSelection(baseOffset: start, extentOffset: end - 1),
            ChangeSource.local,
          );
          return true;
        }
      }
    }

    // 不在代码块内，默认全选
    return false;
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
    _autoScrollTimer?.cancel();
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
      child: Row(
        children: [
          // 左侧：菜单和图片按钮
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _buildParagraphMenu(),
                  _toolbarDivider(),
                  _buildFormatMenu(),
                  _toolbarDivider(),
                  // 粘贴图片按钮
                  IconButton(
                    icon: const Icon(LucideIcons.clipboardPaste, size: 20),
                    onPressed: _pasteImageFromClipboard,
                    tooltip: '粘贴图片',
                  ),
                  // 选择图片按钮
                  IconButton(
                    icon: const Icon(LucideIcons.imagePlus, size: 20),
                    onPressed: _pickImageFromFile,
                    tooltip: '选择图片',
                  ),
                ],
              ),
            ),
          ),
          // 右侧：大纲按钮
          Tooltip(
            message: _showOutline ? '关闭大纲' : '打开大纲',
            child: IconButton(
              icon: Icon(
                LucideIcons.listTree,
                size: 20,
                color: _showOutline
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              onPressed: () => setState(() => _showOutline = !_showOutline),
            ),
          ),
          // 右侧：中英文格式化
          Tooltip(
            message: '中英文格式化',
            child: IconButton(
              icon: const Icon(LucideIcons.sparkles, size: 20),
              onPressed: () => CnEnFormatter.formatDocument(_controller),
              tooltip: '中英文格式化',
            ),
          ),
        ],
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
          Icon(LucideIcons.type, size: 20),
          SizedBox(width: 2),
          // Text('段落', style: TextStyle(fontSize: 12)),
          Icon(LucideIcons.chevronDown, size: 14),
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
          Icon(LucideIcons.caseSensitive, size: 20),
          SizedBox(width: 2),
          // Text('格式', style: TextStyle(fontSize: 12)),
          Icon(LucideIcons.chevronDown, size: 14),
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

  /// 代码块语法高亮主题色
  static const _codeColors = {
    'keyword': Color(0xFFC678DD),
    'built_in': Color(0xFFE5C07B),
    'type': Color(0xFFE5C07B),
    'literal': Color(0xFFD19A66),
    'number': Color(0xFFD19A66),
    'regexp': Color(0xFF98C379),
    'string': Color(0xFF98C379),
    'subst': Color(0xFFE06C75),
    'symbol': Color(0xFF61AFEF),
    'class': Color(0xFFE5C07B),
    'function': Color(0xFF61AFEF),
    'title': Color(0xFF61AFEF),
    'params': Color(0xFFABB2BF),
    'comment': Color(0xFF7F848E),
    'doctag': Color(0xFFC678DD),
    'meta': Color(0xFFABB2BF),
    'section': Color(0xFFE06C75),
    'tag': Color(0xFFE06C75),
    'name': Color(0xFFE06C75),
    'attr': Color(0xFFD19A66),
    'attribute': Color(0xFF98C379),
    'variable': Color(0xFFE06C75),
    'bullet': Color(0xFFD19A66),
    'code': Color(0xFF98C379),
    'emphasis': Color(0xFFC678DD),
    'strong': Color(0xFFE5C07B),
    'formula': Color(0xFFC678DD),
    'addition': Color(0xFF98C379),
    'deletion': Color(0xFFE06C75),
  };

  /// 自定义 textSpanBuilder：代码块内语法高亮
  InlineSpan _codeHighlightSpanBuilder(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    // node 是 Leaf（QuillText），parent 是 Line，Line.parent 是 Block
    final line = node.parent;
    if (line is! Line) {
      return TextSpan(
        text: text,
        style: style,
        recognizer: recognizer,
        mouseCursor: recognizer != null ? SystemMouseCursors.click : null,
      );
    }

    final block = line.parent;
    if (block is! Block || !block.style.attributes.containsKey(Attribute.codeBlock.key)) {
      return TextSpan(
        text: text,
        style: style,
        recognizer: recognizer,
        mouseCursor: recognizer != null ? SystemMouseCursors.click : null,
      );
    }

    // 读取代码块语言，默认 dart
    String lang = 'dart';
    final blockOffset = block.first?.documentOffset ?? -1;
    if (_codeBlockLanguages.containsKey(blockOffset)) {
      final langValue = _codeBlockLanguages[blockOffset]!.toLowerCase();
      if (languages.allLanguages.containsKey(langValue)) {
        lang = langValue;
      }
    }

    // 代码块语法高亮
    final fullLineText = _getFullLineText(line);
    final result = highlight.highlight.parse(fullLineText, language: lang);
    final baseStyle = style?.copyWith(fontFamily: 'monospace') ??
        const TextStyle(fontFamily: 'monospace');

    return _buildHighlightedSpan(result.nodes, baseStyle, recognizer);
  }

  /// 获取 Line 的完整文本内容
  String _getFullLineText(Line line) {
    final buffer = StringBuffer();
    for (final child in line.children) {
      if (child is Leaf) {
        buffer.write(child.toPlainText());
      }
    }
    return buffer.toString();
  }

  /// 从 highlight 解析结果构建 TextSpan
  TextSpan _buildHighlightedSpan(
    List<highlight.Node>? nodes,
    TextStyle baseStyle,
    GestureRecognizer? recognizer,
  ) {
    if (nodes == null || nodes.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    final children = <TextSpan>[];
    for (final node in nodes) {
      if (node.value != null) {
        children.add(TextSpan(
          text: node.value,
          style: node.className != null
              ? baseStyle.copyWith(
                  color: _codeColors[node.className],
                )
              : baseStyle,
        ));
      } else if (node.children != null) {
        final childSpan = _buildHighlightedSpan(
          node.children,
          node.className != null
              ? baseStyle.copyWith(color: _codeColors[node.className])
              : baseStyle,
          recognizer,
        );
        children.add(childSpan);
      }
    }

    return TextSpan(
      children: children,
      style: baseStyle,
      recognizer: recognizer,
      mouseCursor: recognizer != null ? SystemMouseCursors.click : null,
    );
  }

  /// 自定义代码块 leading：在第一行上方渲染 header
  static const _langOptions = [
    'dart', 'java', 'javascript', 'typescript', 'python', 'sql',
    'kotlin', 'swift', 'go', 'rust', 'c', 'cpp', 'csharp',
    'ruby', 'php', 'html', 'css', 'json', 'yaml', 'xml',
    'bash', 'shell', 'markdown', 'plaintext',
  ];

  Widget? _buildLeadingBlock(Node node, LeadingConfig config) {
    if (config.attribute.key != Attribute.codeBlock.key) return null;

    final line = node;
    if (line is! Line) return null;

    final block = line.parent;
    if (block is! Block) return null;

    // 只在代码块第一行显示 header
    if (block.first != line) return null;

    final blockOffset = block.first?.documentOffset ?? -1;
    final currentLang = _codeBlockLanguages[blockOffset] ?? 'dart';

    const headerHeight = 28.0;
    final headerWidth = _editorContentWidth > 0
        ? _editorContentWidth
        : MediaQuery.of(context).size.width - _editorHorizontalPadding * 2;
    const headerColor = Color(0xFFF1F1F1);

    final langKey = _langLabelKeys.putIfAbsent(blockOffset, () => GlobalKey(debugLabel: 'langLabel'));
    final copyKey = _copyButtonKeys.putIfAbsent(blockOffset, () => GlobalKey(debugLabel: 'copyBtn'));

    return SizedBox(
      height: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -headerHeight,
            left: -16,
            child: Container(
              width: headerWidth,
              height: headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
              ),
              child: Row(
                children: [
                  // 语言标签（点击通过 Listener 在外层处理）
                  MouseRegion(
                    key: langKey,
                    cursor: SystemMouseCursors.click,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentLang.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // 复制按钮（点击通过 Listener 在外层处理）
                  MouseRegion(
                    key: copyKey,
                    cursor: SystemMouseCursors.click,
                    child: Tooltip(
                      message: '复制代码',
                      child: Icon(
                        Icons.copy,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 弹出语言选择器
  void _showLanguagePicker(int blockOffset, String currentLang) {
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      constraints: const BoxConstraints(maxHeight: 300),
      position: RelativeRect.fromLTRB(
        position.dx + 100,
        position.dy + 60,
        position.dx + 200,
        position.dy + 60,
      ),
      items: _langOptions
          .map((lang) => PopupMenuItem(
                value: lang,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      lang,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: lang == currentLang
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    if (lang == currentLang) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ))
          .toList(),
    ).then((value) {
      if (value != null) {
        setState(() {
          _codeBlockLanguages[blockOffset] = value;
        });
        _persistCodeBlockLang(blockOffset, value);
      }
    });
  }

  /// 是否正在拖拽选择文本
  bool _isDragging = false;

  /// 自动滚动定时器
  Timer? _autoScrollTimer;

  /// 自动滚动方向和速度（正=向下，负=向上，0=停止）
  double _autoScrollVelocity = 0;

  @override
  Widget build(BuildContext context) {
    final editorWidget = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _isDragging = true;
        _headerPointerDown = event.position;
      },
      onPointerUp: (event) {
        _isDragging = false;
        _autoScrollVelocity = 0;
        _autoScrollTimer?.cancel();
        _autoScrollTimer = null;
        // 检测代码块 header 区域的点击
        if (_headerPointerDown != null &&
            (event.position - _headerPointerDown!).distance < 20) {
          _handleHeaderTap(event.position);
        }
        _headerPointerDown = null;
      },
      onPointerCancel: (_) {
        _isDragging = false;
        _autoScrollVelocity = 0;
        _autoScrollTimer?.cancel();
        _autoScrollTimer = null;
      },
      onPointerMove: (event) {
        if (!_isDragging) return;
        _handleAutoScroll(event.localPosition, event.kind);
      },
      onPointerSignal: _handlePointerSignal,
      child: LayoutBuilder(builder: (context, boxConstraints) {
        _editorContentWidth = boxConstraints.maxWidth - _editorHorizontalPadding * 2;
        final defaultStyles = DefaultStyles.getInstance(context);
        return QuillStyles(
            data: defaultStyles.merge(DefaultStyles(
              code: DefaultTextBlockStyle(
                defaultStyles.code!.style,
                defaultStyles.code!.horizontalSpacing,
                defaultStyles.code!.verticalSpacing,
                defaultStyles.code!.lineSpacing,
                const BoxDecoration(
                  color: Color(0xFFEDEDED),
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            )),
            child: QuillEditor(
              controller: _controller,
              focusNode: _focusNode,
              scrollController: _scrollController,
              config: QuillEditorConfig(
                padding: const EdgeInsets.only(left: _editorHorizontalPadding, top: 16, right: _editorHorizontalPadding, bottom: 16),
                placeholder: '开始输入...',
                autoFocus: false,
                textSpanBuilder: _codeHighlightSpanBuilder,
                customLeadingBlockBuilder: _buildLeadingBlock,
                embedBuilders: [
                  _ImageEmbedBuilder(controller: _controller),
                ],
              ),
            ),
          );
      }),
    );

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _showOutline
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: editorWidget),
                    _buildDragHandle(),
                    SizedBox(
                      width: _outlineWidth.clamp(160.0, 400.0),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Theme.of(context).dividerColor),
                          ),
                        ),
                        child: OutlineSidebar(
                          controller: _controller,
                          editorScrollController: _scrollController,
                        ),
                      ),
                    ),
                  ],
                )
              : editorWidget,
        ),
      ],
    );
  }

  Widget _buildDragHandle() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _outlineWidth = (_outlineWidth - details.delta.dx).clamp(160.0, 400.0);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  /// 检测代码块 header 区域的点击
  void _handleHeaderTap(Offset globalPosition) {
    // 检测语言标签点击
    for (final entry in _langLabelKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;
      final pos = renderBox.localToGlobal(Offset.zero);
      final rect = pos & renderBox.size;
      if (rect.contains(globalPosition)) {
        final currentLang = _codeBlockLanguages[entry.key] ?? 'dart';
        _showLanguagePicker(entry.key, currentLang);
        return;
      }
    }
    // 检测复制按钮点击
    for (final entry in _copyButtonKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;
      final pos = renderBox.localToGlobal(Offset.zero);
      final rect = pos & renderBox.size;
      if (rect.contains(globalPosition)) {
        _copyCodeBlock(entry.key);
        return;
      }
    }
  }

  /// 复制指定偏移量处的代码块内容
  void _copyCodeBlock(int blockOffset) {
    final block = _findBlockAtOffset(blockOffset);
    if (block == null) return;
    _doCopyBlock(block);
  }

  void _doCopyBlock(Block block) {
    final buffer = StringBuffer();
    for (final child in block.children) {
      if (child is Line) {
        buffer.writeln(child.toPlainText());
      }
    }
    final text = buffer.toString().trimRight();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('复制成功'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// 根据指针位置计算自动滚动速度
  void _handleAutoScroll(Offset localPosition, PointerDeviceKind kind) {
    if (kind != PointerDeviceKind.mouse && kind != PointerDeviceKind.touch) {
      return;
    }

    final box = context.findRenderObject() as RenderBox;
    final editorHeight = box.size.height;
    final toolbarHeight = 48.0;
    final availableHeight = editorHeight - toolbarHeight;
    final y = localPosition.dy - toolbarHeight;

    const edgeZone = 40.0;

    if (y > availableHeight - edgeZone) {
      // 靠近底部，向下滚动
      final overflow = (y - (availableHeight - edgeZone)).clamp(0.0, edgeZone);
      _autoScrollVelocity = (overflow / edgeZone) * 15.0;
    } else if (y < edgeZone) {
      // 靠近顶部，向上滚动
      final underflow = (edgeZone - y).clamp(0.0, edgeZone);
      _autoScrollVelocity = -(underflow / edgeZone) * 15.0;
    } else {
      _autoScrollVelocity = 0;
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }

    _startAutoScroll();
  }

  /// 启动自动滚动定时器
  void _startAutoScroll() {
    if (_autoScrollTimer?.isActive == true) return;

    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (!_isDragging || _autoScrollVelocity == 0) {
          _autoScrollTimer?.cancel();
          _autoScrollTimer = null;
          return;
        }
        if (!_scrollController.hasClients) return;

        final pos = _scrollController.position;
        final target = (pos.pixels + _autoScrollVelocity)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
        _scrollController.jumpTo(target);
      },
    );
  }

  /// 处理滚轮事件，修复代码块区域滚动被阻断
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;

    final before = pos.pixels;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final after = _scrollController.position.pixels;
      if ((after - before).abs() < 0.5) {
        final target = (_scrollController.position.pixels + event.scrollDelta.dy)
            .clamp(_scrollController.position.minScrollExtent,
                _scrollController.position.maxScrollExtent);
        if ((target - _scrollController.position.pixels).abs() > 0.5) {
          _scrollController.jumpTo(target);
        }
      }
    });
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

    // 提取文档中所有图片路径和当前图片的索引
    final allImages = _collectImageSources();
    final currentIndex = allImages.indexOf(source);

    return _ResizableImage(
      source: source,
      initialWidth: width,
      allImages: allImages,
      currentIndex: currentIndex >= 0 ? currentIndex : 0,
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

  /// 收集文档中所有图片的 source 路径（按出现顺序）
  List<String> _collectImageSources() {
    final sources = <String>[];
    for (final op in controller.document.toDelta().toList()) {
      if (op.data is Map) {
        final data = op.data as Map;
        if (data.containsKey('image')) {
          final raw = data['image'] as String;
          try {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            final src = json['source'] as String?;
            if (src != null) sources.add(src);
          } catch (_) {
            sources.add(raw);
          }
        }
      }
    }
    return sources;
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
  final List<String> allImages;
  final int currentIndex;

  const _ResizableImage({
    required this.source,
    required this.initialWidth,
    required this.onWidthChanged,
    required this.onDelete,
    required this.allImages,
    required this.currentIndex,
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
        pageBuilder: (_, __, ___) => _ImagePreviewOverlay(
          images: widget.allImages,
          initialIndex: widget.currentIndex,
        ),
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

/// 图片原图预览浮层（支持滚轮缩放、拖拽平移、多图导航）
class _ImagePreviewOverlay extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _ImagePreviewOverlay({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_ImagePreviewOverlay> createState() => _ImagePreviewOverlayState();
}

class _ImagePreviewOverlayState extends State<_ImagePreviewOverlay> {
  late int _currentIndex;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _goToImage(int index) {
    setState(() {
      _currentIndex = index;
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  Widget _buildImage(String source) {
    final isNetwork = source.startsWith('http://') || source.startsWith('https://');
    return isNetwork
        ? Image.network(source, fit: BoxFit.contain)
        : Image.file(File(source), fit: BoxFit.contain);
  }

  Widget _buildThumbnail(String source, int index, bool isActive) {
    const size = 40.0;
    final isNetwork = source.startsWith('http://') || source.startsWith('https://');
    return GestureDetector(
      onTap: () => _goToImage(index),
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          border: isActive
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.white24, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: isNetwork
              ? Image.network(source, fit: BoxFit.cover)
              : Image.file(File(source), fit: BoxFit.cover),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < widget.images.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: (event) {
          if (event is! KeyDownEvent) return;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && hasPrev) {
            _goToImage(_currentIndex - 1);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight && hasNext) {
            _goToImage(_currentIndex + 1);
          }
        },
        child: Listener(
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
            child: Container(
              color: Colors.black.withValues(alpha: 0.05),
              width: double.infinity,
              height: double.infinity,
              child: Stack(
                children: [
                  // 图片
                  Center(
                    child: Transform.translate(
                      offset: _offset,
                      child: Transform.scale(
                        scale: _scale,
                        child: Transform.scale(
                          scale: _scale,
                          child: _buildImage(widget.images[_currentIndex]),
                        ),
                      ),
                    ),
                  ),
                  // 左箭头
                  if (hasPrev)
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton(
                          onPressed: () => _goToImage(_currentIndex - 1),
                          icon: const Icon(Icons.chevron_left, size: 36),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // 右箭头
                  if (hasNext)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton(
                          onPressed: () => _goToImage(_currentIndex + 1),
                          icon: const Icon(Icons.chevron_right, size: 36),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // 底部缩略图条
                  if (widget.images.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 480),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < widget.images.length; i++)
                                _buildThumbnail(
                                  widget.images[i],
                                  i,
                                  i == _currentIndex,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
