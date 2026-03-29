import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// ignore: depend_on_referenced_packages

/// Markdown 编辑器组件
class MarkdownEditor extends StatefulWidget {
  final String initialContent;
  final Function(String) onContentChanged;
  final bool isDesktop;

  const MarkdownEditor({
    super.key,
    required this.initialContent,
    required this.onContentChanged,
    this.isDesktop = false,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _showPreview = false;
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _previewScrollController = ScrollController();
  bool _isSyncingScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(_onContentChanged);

    // 桌面端滚动同步
    if (widget.isDesktop) {
      _editorScrollController.addListener(_syncEditorScrollToPreview);
    }
  }

  void _syncEditorScrollToPreview() {
    if (_isSyncingScroll ||
        !_editorScrollController.hasClients ||
        !_previewScrollController.hasClients) {
      return;
    }

    _isSyncingScroll = true;

    // 计算滚动比例
    final editorMaxScroll = _editorScrollController.position.maxScrollExtent;
    final editorOffset = _editorScrollController.offset;
    final previewMaxScroll = _previewScrollController.position.maxScrollExtent;

    if (editorMaxScroll > 0 && previewMaxScroll > 0) {
      final ratio = previewMaxScroll / editorMaxScroll;
      final targetOffset = (editorOffset * ratio).clamp(0.0, previewMaxScroll);
      _previewScrollController.jumpTo(targetOffset);
    }

    _isSyncingScroll = false;
  }

  void _onContentChanged() {
    widget.onContentChanged(_controller.text);
  }

  @override
  void didUpdateWidget(MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialContent != widget.initialContent &&
        _controller.text != widget.initialContent) {
      _controller.text = widget.initialContent;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onContentChanged);
    _controller.dispose();
    _focusNode.dispose();
    _editorScrollController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  /// 插入 Markdown 语法
  void _insertMarkdown(String before, [String after = '']) {
    final text = _controller.text;
    final selection = _controller.selection;
    final selectedText = selection.textInside(text);

    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$before$selectedText$after',
    );

    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: selection.start + before.length + selectedText.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 桌面端：分屏视图
    if (widget.isDesktop) {
      return Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              children: [
                // 编辑器
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: _buildEditor(),
                  ),
                ),
                // 预览
                Expanded(child: _buildPreview()),
              ],
            ),
          ),
        ],
      );
    }

    // 移动端：切换视图
    return Column(
      children: [
        _buildToolbar(),
        Expanded(child: _showPreview ? _buildPreview() : _buildEditor()),
        // 预览切换按钮
        Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('编辑')),
                  ButtonSegment(value: true, label: Text('预览')),
                ],
                selected: {_showPreview},
                onSelectionChanged: (Set<bool> selection) {
                  setState(() {
                    _showPreview = selection.first;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

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
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _buildToolButton(Icons.title, () => _insertMarkdown('## ', '')),
            _buildToolButton(
              Icons.format_bold,
              () => _insertMarkdown('**', '**'),
            ),
            _buildToolButton(
              Icons.format_italic,
              () => _insertMarkdown('*', '*'),
            ),
            _buildToolButton(Icons.code, () => _insertMarkdown('`', '`')),
            _buildToolButton(Icons.link, () => _insertMarkdown('[', '](url)')),
            _buildToolButton(
              Icons.format_quote,
              () => _insertMarkdown('> ', ''),
            ),
            _buildToolButton(
              Icons.format_list_numbered,
              () => _insertMarkdown('1. ', ''),
            ),
            _buildToolButton(
              Icons.format_list_bulleted,
              () => _insertMarkdown('- ', ''),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton(IconData icon, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      tooltip: _getTooltip(icon),
    );
  }

  String _getTooltip(IconData icon) {
    switch (icon) {
      case Icons.title:
        return '标题';
      case Icons.format_bold:
        return '粗体';
      case Icons.format_italic:
        return '斜体';
      case Icons.code:
        return '代码';
      case Icons.link:
        return '链接';
      case Icons.format_quote:
        return '引用';
      case Icons.format_list_numbered:
        return '有序列表';
      case Icons.format_list_bulleted:
        return '无序列表';
      default:
        return '';
    }
  }

  Widget _buildEditor() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: '开始输入 Markdown...',
        ),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Markdown(
        data: _controller.text,
        extensionSet: md.ExtensionSet.gitHubWeb,
        padding: const EdgeInsets.all(16),
        controller: _previewScrollController,
        styleSheet: MarkdownStyleSheet(
          h1: Theme.of(context).textTheme.headlineLarge,
          h2: Theme.of(context).textTheme.headlineMedium,
          h3: Theme.of(context).textTheme.headlineSmall,
          p: Theme.of(context).textTheme.bodyLarge,
          code: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
          codeblockDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
