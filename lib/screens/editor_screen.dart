import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/note_storage_service.dart';
import '../widgets/rich_text_editor.dart';
import '../widgets/markdown_editor.dart';

/// 编辑器页面
class EditorScreen extends StatefulWidget {
  final Note note;
  final NoteStorageService storageService;

  const EditorScreen({
    super.key,
    required this.note,
    required this.storageService,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late Note _currentNote;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
  }

  void _onContentChanged(String content) {
    // 提取标题（从内容的第一行）
    final title = _extractTitle(content);

    setState(() {
      _currentNote = _currentNote.copyWith(
        content: content,
        title: title,
        updatedAt: DateTime.now(),
      );
      _hasChanges = true;
    });

    // 触发自动保存
    widget.storageService.scheduleAutoSave(_currentNote);
  }

  String _extractTitle(String content) {
    if (content.isEmpty) return '';

    if (_currentNote.type == 'markdown') {
      // Markdown：提取第一个标题或非空行
      final lines = content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('#')) {
          return trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        }
        if (trimmed.isNotEmpty && !trimmed.startsWith('```')) {
          return trimmed.length > 50
              ? '${trimmed.substring(0, 50)}...'
              : trimmed;
        }
      }
      return '';
    } else {
      // 富文本：尝试从 Delta JSON 提取（简化处理）
      return '富文本笔记';
    }
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'share':
        // TODO: 实现分享功能
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('分享功能开发中')));
        }
        break;
      case 'duplicate':
        // 复制笔记
        final duplicatedNote = _currentNote.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '${_currentNote.title} (副本)',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final result = await widget.storageService.saveNote(duplicatedNote);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.success ? '笔记已复制' : (result.error ?? '复制失败')),
            ),
          );
        }
        break;
      case 'delete':
        // 显示删除确认对话框
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除笔记'),
            content: const Text('确定要删除这篇笔记吗？此操作无法撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          final result = await widget.storageService.deleteNote(_currentNote.id);
          if (result.success && mounted) {
            Navigator.of(context).pop();
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.error ?? '删除失败')),
            );
          }
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRichText = _currentNote.type == 'rich_text';
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop && _hasChanges) {
          await widget.storageService.flushAutoSave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (_hasChanges) {
                await widget.storageService.flushAutoSave();
              }
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            _currentNote.title.isEmpty ? '无标题' : _currentNote.title,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_hasChanges)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('已保存', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 4),
                    Icon(Icons.cloud_done_outlined, size: 20),
                  ],
                ),
              ),
            PopupMenuButton<String>(
              onSelected: _handleMenuAction,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share),
                    title: Text('分享'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: ListTile(
                    leading: Icon(Icons.copy),
                    title: Text('复制笔记'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('删除', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        body: isRichText
            ? RichTextEditor(
                initialContent: _currentNote.content,
                onContentChanged: _onContentChanged,
              )
            : MarkdownEditor(
                initialContent: _currentNote.content,
                onContentChanged: _onContentChanged,
                isDesktop: isDesktop,
              ),
      ),
    );
  }
}
