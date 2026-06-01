import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

class OutlineItem {
  final int level;
  final String text;
  final int offset;

  const OutlineItem({
    required this.level,
    required this.text,
    required this.offset,
  });
}

class OutlineSidebar extends StatefulWidget {
  final QuillController controller;
  final ScrollController editorScrollController;

  const OutlineSidebar({
    super.key,
    required this.controller,
    required this.editorScrollController,
  });

  @override
  State<OutlineSidebar> createState() => _OutlineSidebarState();
}

class _OutlineSidebarState extends State<OutlineSidebar> {
  List<OutlineItem> _items = [];
  int? _activeIndex;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _extractOutline();
    widget.controller.addListener(_onDocumentChanged);
    widget.controller.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onDocumentChanged);
    widget.controller.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onDocumentChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _extractOutline();
    });
  }

  void _onSelectionChanged() {
    final selection = widget.controller.selection;
    if (!selection.isValid) return;

    final offset = selection.baseOffset;
    int? newActive;
    for (int i = _items.length - 1; i >= 0; i--) {
      if (_items[i].offset <= offset) {
        newActive = i;
        break;
      }
    }
    if (newActive != _activeIndex && mounted) {
      setState(() => _activeIndex = newActive);
    }
  }

  void _extractOutline() {
    final items = <OutlineItem>[];
    for (final node in widget.controller.document.root.children) {
      int? headerLevel;
      String text = '';

      if (node is Line) {
        final attrs = node.style.attributes;
        if (attrs.containsKey(Attribute.header.key)) {
          headerLevel = attrs[Attribute.header.key]?.value as int?;
        }
        if (headerLevel != null) {
          text = node.toPlainText().trim();
        }
      } else if (node is Block) {
        for (final child in node.children) {
          if (child is Line) {
            final attrs = child.style.attributes;
            if (attrs.containsKey(Attribute.header.key)) {
              headerLevel = attrs[Attribute.header.key]?.value as int?;
              if (headerLevel != null) {
                text = child.toPlainText().trim();
                break;
              }
            }
          }
        }
      }

      if (headerLevel != null && headerLevel >= 1 && headerLevel <= 3 && text.isNotEmpty) {
        items.add(OutlineItem(
          level: headerLevel,
          text: text,
          offset: node.documentOffset,
        ));
      }
    }

    if (mounted) {
      setState(() {
        _items = items;
        _activeIndex = null;
      });
      _onSelectionChanged();
    }
  }

  void _jumpTo(int offset) {
    final selection = TextSelection.collapsed(offset: offset);
    widget.controller.updateSelection(selection, ChangeSource.local);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.editorScrollController.hasClients) {
        final pos = widget.editorScrollController.position;
        if (pos.hasContentDimensions) {
          final max = pos.maxScrollExtent;
          final target = (offset / widget.controller.document.length * max)
              .clamp(pos.minScrollExtent, max);
          widget.editorScrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            '大纲',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Text(
                    '暂无标题',
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isActive = index == _activeIndex;
                    final indent = (item.level - 1) * 12.0;

                    return InkWell(
                      onTap: () => _jumpTo(item.offset),
                      child: Container(
                        padding: EdgeInsets.only(
                          left: 12 + indent,
                          right: 12,
                          top: 6,
                          bottom: 6,
                        ),
                        decoration: isActive
                            ? BoxDecoration(
                                color: theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                              )
                            : null,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: item.level == 1
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isActive
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
