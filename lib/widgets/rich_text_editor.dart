import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:convert';
import '../utils/markdown_auto_converter.dart';

/// 富文本编辑器组件
class RichTextEditor extends StatefulWidget {
  final String initialContent;
  final Function(String) onContentChanged;

  const RichTextEditor({
    super.key,
    required this.initialContent,
    required this.onContentChanged,
  });

  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  late QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isInitialized = false;

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
      // 如果解析失败，创建空文档
      _controller = QuillController.basic();
    }

    // 监听内容变化
    _controller.addListener(_onContentChanged);
    _isInitialized = true;

    // 初始化 Markdown 自动转换器
    _markdownConverter = MarkdownAutoConverter(
      controller: _controller,
      enabled: _markdownEnabled,
    );
  }

  void _onContentChanged() {
    if (!_isInitialized) return;

    // 检测 Markdown 触发
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

    // 检测空格触发（块级语法）
    if (char == ' ') {
      _markdownConverter!.handleTextChange('space');
    }
    // 检测回车触发（块级语法）
    else if (char == '\n') {
      _markdownConverter!.handleTextChange('enter');
    }
    // 检测行内语法完成触发
    else if (char == '*' || char == '_' || char == '`' || char == '~') {
      _markdownConverter!.handleTextChange('inline');
    }
  }

  @override
  void didUpdateWidget(RichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 不在编辑时重新初始化控制器
    // 只在第一次初始化时设置内容
  }

  @override
  void dispose() {
    _controller.removeListener(_onContentChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 工具栏
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: QuillSimpleToolbar(
                  controller: _controller,
                  config: QuillSimpleToolbarConfig(
                    showAlignmentButtons: true,
                    showBoldButton: true,
                    showItalicButton: true,
                    showUnderLineButton: true,
                    showStrikeThrough: true,
                    showHeaderStyle: true,
                    showListBullets: true,
                    showListNumbers: true,
                    showUndo: true,
                    showRedo: true,
                    multiRowsDisplay: false,
                  ),
                ),
              ),
              // Markdown 开关按钮
              Tooltip(
                message: _markdownEnabled
                    ? 'Markdown 自动转换：开'
                    : 'Markdown 自动转换：关',
                child: IconButton(
                  icon: Icon(
                    Icons.code,
                    color: _markdownEnabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  onPressed: toggleMarkdown,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        // 编辑器
        Expanded(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: QuillEditor(
              controller: _controller,
              focusNode: _focusNode,
              scrollController: _scrollController,
              config: const QuillEditorConfig(
                padding: EdgeInsets.all(16),
                placeholder: '开始输入...',
                autoFocus: false,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
