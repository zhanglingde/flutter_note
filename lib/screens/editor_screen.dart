import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/note_storage_service.dart';
import '../services/sync/asset_repository.dart';
import '../widgets/rich_text_editor.dart';

/// 编辑器页面
class EditorScreen extends StatefulWidget {
  final Note note;
  final NoteStorageService storageService;
  final AssetRepository assetRepository;

  const EditorScreen({
    super.key,
    required this.note,
    required this.storageService,
    required this.assetRepository,
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
    setState(() {
      _currentNote = _currentNote.copyWith(
        content: content,
        updatedAt: DateTime.now(),
      );
      _hasChanges = true;
    });

    // 触发自动保存
    widget.storageService.scheduleAutoSave(_currentNote);
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
              content: Text(
                result.success ? '笔记已复制' : (result.error ?? '复制失败'),
              ),
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
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFEDEDED),
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          final result = await widget.storageService.deleteNote(
            _currentNote.id,
          );
          if (result.success && mounted) {
            Navigator.of(context).pop();
          } else if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(result.error ?? '删除失败')));
          }
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
          title: TextField(
            controller: TextEditingController(text: _currentNote.title)
              ..selection = TextSelection.collapsed(
                offset: _currentNote.title.length,
              ),
            decoration: const InputDecoration(
              hintText: '输入标题...',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: Theme.of(context).textTheme.titleMedium,
            onChanged: (value) {
              setState(() {
                _currentNote = _currentNote.copyWith(
                  title: value,
                  updatedAt: DateTime.now(),
                );
                _hasChanges = true;
              });
              widget.storageService.scheduleAutoSave(_currentNote);
            },
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
        body: RichTextEditor(
          initialContent: _currentNote.content,
          onContentChanged: _onContentChanged,
          noteId: _currentNote.id,
          storageService: widget.storageService,
          assetRepository: widget.assetRepository,
          onClipToNewNote: (deltaJson) async {
            final now = DateTime.now();
            final title = _extractTitle(deltaJson);
            final note = Note(
              id: now.millisecondsSinceEpoch.toString(),
              title: title,
              content: deltaJson,
              type: 'rich_text',
              createdAt: now,
              updatedAt: now,
            );
            await widget.storageService.saveNote(note);
            if (context.mounted) {
              await Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => EditorScreen(
                    note: note,
                    storageService: widget.storageService,
                    assetRepository: widget.assetRepository,
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}

String _extractTitle(String content) {
  if (content.isEmpty) return '';
  try {
    final delta = jsonDecode(content) as List<dynamic>;
    final buffer = StringBuffer();
    for (final op in delta) {
      if (op is Map<String, dynamic> && op['insert'] is String) {
        buffer.write(op['insert']);
      }
    }
    final lines = buffer.toString().split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.length > 50
            ? '${trimmed.substring(0, 50)}...'
            : trimmed;
      }
    }
    return '';
  } catch (e) {
    return '';
  }
}
