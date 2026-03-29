import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:convert';

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
  }

  void _onContentChanged() {
    if (!_isInitialized) return;
    final json = jsonEncode(_controller.document.toDelta().toJson());
    widget.onContentChanged(json);
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
