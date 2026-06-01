import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/note_storage_service.dart';
import '../services/image_storage_service.dart';
import '../widgets/rich_text_editor.dart';

/// 首页 - 笔记列表
class HomeScreen extends StatefulWidget {
  final NoteStorageService storageService;

  const HomeScreen({super.key, required this.storageService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Note> _notes = [];
  String _searchQuery = '';
  bool _isLoading = true;
  Note? _selectedNote;
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    final result = await widget.storageService.loadNotesSortedByUpdatedAt();
    if (result.success && result.data != null) {
      setState(() {
        _notes = result.data!;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.error ?? '加载笔记失败')));
      }
    }
  }

  List<Note> get _filteredNotes {
    if (_searchQuery.isEmpty) return _notes;
    return _notes.where((note) {
      final lowerQuery = _searchQuery.toLowerCase();
      return note.title.toLowerCase().contains(lowerQuery) ||
          note.content.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  Future<void> _createNote() async {
    final now = DateTime.now();
    final note = Note(
      id: now.millisecondsSinceEpoch.toString(),
      title: '',
      content: '[]',
      type: 'rich_text',
      createdAt: now,
      updatedAt: now,
    );

    final result = await widget.storageService.saveNote(note);
    if (result.success && mounted) {
      final isDesktop = MediaQuery.of(context).size.width > 768;
      if (isDesktop) {
        _loadNotes();
        _selectNote(note);
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => _EditorScreenWrapper(
              note: note,
              storageService: widget.storageService,
            ),
          ),
        );
        _loadNotes();
      }
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error ?? '创建笔记失败')));
    }
  }

  Future<void> _openNote(Note note) async {
    final isDesktop = MediaQuery.of(context).size.width > 768;
    if (isDesktop) {
      _selectNote(note);
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _EditorScreenWrapper(
            note: note,
            storageService: widget.storageService,
          ),
        ),
      );
      _loadNotes();
    }
  }

  void _selectNote(Note note) {
    setState(() {
      _selectedNote = note;
      _titleController.text = note.title;
    });
  }

  void _onContentChanged(String content) {
    if (_selectedNote == null) return;
    setState(() {
      _selectedNote = _selectedNote!.copyWith(
        content: content,
        updatedAt: DateTime.now(),
      );
    });
    _updateNoteInList(_selectedNote!);
    widget.storageService.scheduleAutoSave(_selectedNote!);
  }

  void _onTitleChanged(String value) {
    if (_selectedNote == null) return;
    setState(() {
      _selectedNote = _selectedNote!.copyWith(
        title: value,
        updatedAt: DateTime.now(),
      );
    });
    _updateNoteInList(_selectedNote!);
    widget.storageService.scheduleAutoSave(_selectedNote!);
  }

  void _updateNoteInList(Note updated) {
    final index = _notes.indexWhere((n) => n.id == updated.id);
    if (index >= 0) {
      setState(() {
        _notes[index] = updated;
        _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      });
    }
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text('确定要删除 "${note.title.isEmpty ? "无标题" : note.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await widget.storageService.deleteNote(note.id);
      if (result.success) {
        await ImageStorageService().deleteImagesForNote(note.id);
        if (_selectedNote?.id == note.id) {
          setState(() => _selectedNote = null);
        }
        _loadNotes();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.error ?? '删除笔记失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout();
  }

  /// 桌面端：左右两栏布局
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // 左侧：笔记列表面板
          SizedBox(
            width: 320,
            child: _buildNoteListPanel(),
          ),
          // 分割线
          const VerticalDivider(width: 1),
          // 右侧：编辑器面板
          Expanded(
            child: _selectedNote != null
                ? _buildEditorPanel()
                : _buildEmptyEditorPanel(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 移动端：原有单栏布局
  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final query = await showSearch<String>(
                context: context,
                delegate: NoteSearchDelegate(widget.storageService),
              );
              if (query != null) {
                setState(() => _searchQuery = query);
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildNoteListView(),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 左侧笔记列表面板
  Widget _buildNoteListPanel() {
    return Material(
      child: Column(
        children: [
          AppBar(
            title: const Text('笔记'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () async {
                  final query = await showSearch<String>(
                    context: context,
                    delegate: NoteSearchDelegate(widget.storageService),
                  );
                  if (query != null) {
                    setState(() => _searchQuery = query);
                  }
                },
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildNoteListView(),
          ),
        ],
      ),
    );
  }

  /// 笔记列表
  Widget _buildNoteListView() {
    final notes = _filteredNotes;

    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_alt_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有笔记',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击 + 按钮创建第一个笔记',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotes,
      child: ListView.builder(
        itemCount: notes.length,
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: true,
        itemBuilder: (context, index) {
          final note = notes[index];
          return _buildNoteCard(note);
        },
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    final preview = _getPreview(note.content);
    final isSelected = _selectedNote?.id == note.id;

    return Dismissible(
      key: Key(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteNote(note),
      child: Container(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        child: ListTile(
          selected: isSelected,
          leading: Icon(
            Icons.text_fields,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
          title: Text(
            note.title.isEmpty ? '无标题' : note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(note.updatedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
          onTap: () => _openNote(note),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteNote(note),
          ),
        ),
      ),
    );
  }

  /// 右侧编辑器面板
  Widget _buildEditorPanel() {
    final note = _selectedNote!;

    return Column(
      children: [
        // 编辑器顶栏：标题 + 操作按钮
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    hintText: '输入标题...',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                  onChanged: _onTitleChanged,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (action) => _handleEditorAction(action),
                itemBuilder: (context) => [
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
        ),
        // 编辑器内容
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(note.id),
            child: RichTextEditor(
              initialContent: note.content,
              onContentChanged: _onContentChanged,
              noteId: note.id,
            ),
          ),
        ),
      ],
    );
  }

  /// 右侧空状态面板
  Widget _buildEmptyEditorPanel() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_note,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '选择或创建一个笔记',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  void _handleEditorAction(String action) async {
    if (_selectedNote == null) return;

    switch (action) {
      case 'duplicate':
        final duplicatedNote = _selectedNote!.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '${_selectedNote!.title} (副本)',
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
          if (result.success) _loadNotes();
        }
        break;
      case 'delete':
        await _deleteNote(_selectedNote!);
        break;
    }
  }

  String _getPreview(String content) {
    if (content.isEmpty) return '空笔记';
    try {
      final delta = jsonDecode(content) as List<dynamic>;
      final buffer = StringBuffer();
      for (final op in delta) {
        if (op is Map<String, dynamic> && op['insert'] is String) {
          buffer.write(op['insert']);
        }
      }
      final text = buffer.toString().replaceAll('\n', ' ').trim();
      return text.isEmpty ? '富文本内容' : (text.length > 100 ? '${text.substring(0, 100)}...' : text);
    } catch (e) {
      return content.length > 100 ? '${content.substring(0, 100)}...' : content;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '今天 ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${date.month}月${date.day}日';
    }
  }
}

/// 移动端编辑器页面（从 HomeScreen 导航进入）
class _EditorScreenWrapper extends StatefulWidget {
  final Note note;
  final NoteStorageService storageService;

  const _EditorScreenWrapper({
    required this.note,
    required this.storageService,
  });

  @override
  State<_EditorScreenWrapper> createState() => _EditorScreenWrapperState();
}

class _EditorScreenWrapperState extends State<_EditorScreenWrapper> {
  late Note _currentNote;
  bool _hasChanges = false;
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
    _titleController.text = _currentNote.title;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _onContentChanged(String content) {
    setState(() {
      _currentNote = _currentNote.copyWith(
        content: content,
        updatedAt: DateTime.now(),
      );
      _hasChanges = true;
    });
    widget.storageService.scheduleAutoSave(_currentNote);
  }

  Future<void> _flushAndPop() async {
    if (_hasChanges) {
      await widget.storageService.flushAutoSave();
    }
    if (context.mounted) {
      Navigator.of(context).pop();
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
            onPressed: _flushAndPop,
          ),
          title: TextField(
            controller: _titleController,
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
            PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'delete':
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
                      if (result.success) {
                        await ImageStorageService().deleteImagesForNote(_currentNote.id);
                      }
                      if (result.success && mounted) {
                        Navigator.of(context).pop();
                      }
                    }
                    break;
                }
              },
              itemBuilder: (context) => [
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
        ),
      ),
    );
  }
}

/// 搜索代理
class NoteSearchDelegate extends SearchDelegate<String> {
  final NoteStorageService storageService;

  NoteSearchDelegate(this.storageService);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<StorageResult<List<Note>>>(
      future: storageService.searchNotes(query),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data!;
        final notes = result.success ? (result.data ?? <Note>[]) : <Note>[];
        return _buildResults(notes, context);
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return FutureBuilder<StorageResult<List<Note>>>(
      future: storageService.searchNotes(query),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data!;
        final notes = result.success ? (result.data ?? <Note>[]) : <Note>[];
        return _buildResults(notes, context);
      },
    );
  }

  Widget _buildResults(List<Note> notes, BuildContext context) {
    if (notes.isEmpty) {
      return const Center(child: Text('未找到匹配的笔记'));
    }

    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return ListTile(
          leading: const Icon(Icons.text_fields),
          title: Text(note.title.isEmpty ? '无标题' : note.title),
          subtitle: Text(
            note.content.isEmpty
                ? '空笔记'
                : note.content.substring(
                    0,
                    note.content.length > 50 ? 50 : note.content.length,
                  ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            close(context, query);
          },
        );
      },
    );
  }
}
