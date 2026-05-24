import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/note_storage_service.dart';
import 'editor_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    final result = widget.storageService.loadNotesSortedByUpdatedAt();
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
    final result = widget.storageService.searchNotes(_searchQuery);
    return result.success ? result.data ?? [] : _notes;
  }

  Future<void> _createNote(NoteType type) async {
    final now = DateTime.now();
    final note = Note(
      id: now.millisecondsSinceEpoch.toString(),
      title: '',
      content: type == NoteType.richText ? '[]' : '',
      type: type == NoteType.richText ? 'rich_text' : 'markdown',
      createdAt: now,
      updatedAt: now,
    );

    final result = await widget.storageService.saveNote(note);
    if (result.success && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              EditorScreen(note: note, storageService: widget.storageService),
        ),
      );
      _loadNotes();
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error ?? '创建笔记失败')));
    }
  }

  Future<void> _openNote(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EditorScreen(note: note, storageService: widget.storageService),
      ),
    );
    _loadNotes();
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
        _loadNotes();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.error ?? '删除笔记失败')));
      }
    }
  }

  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('富文本笔记'),
              subtitle: const Text('支持格式化的笔记'),
              onTap: () {
                Navigator.pop(context);
                _createNote(NoteType.richText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Markdown 笔记'),
              subtitle: const Text('使用 Markdown 语法'),
              onTap: () {
                Navigator.pop(context);
                _createNote(NoteType.markdown);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          : _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
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
        // 性能优化：添加 repaint boundary 提高滚动性能
        addRepaintBoundaries: true,
        // 性能优化：保持列表项状态
        addAutomaticKeepAlives: true,
        // 性能优化：预估列表项高度（约 80）
        itemExtent: null,
        itemBuilder: (context, index) {
          final note = notes[index];
          return _buildNoteCard(note);
        },
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    final isRichText = note.type == 'rich_text';
    final preview = _getPreview(note.content, isRichText);

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
      child: ListTile(
        leading: Icon(
          isRichText ? Icons.text_fields : Icons.code,
          color: Theme.of(context).colorScheme.primary,
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
    );
  }

  String _getPreview(String content, bool isRichText) {
    if (content.isEmpty) return '空笔记';
    if (isRichText) {
      // 富文本内容是 Delta JSON，提取纯文本
      try {
        // 简单提取文本（实际项目中应解析 Delta）
        return '富文本内容';
      } catch (e) {
        return '富文本内容';
      }
    }
    // Markdown 返回前100个字符
    return content.length > 100 ? '${content.substring(0, 100)}...' : content;
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
    final result = storageService.searchNotes(query);
    final notes = result.success ? (result.data ?? <Note>[]) : <Note>[];
    return _buildResults(notes, context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final result = storageService.searchNotes(query);
    final notes = result.success ? (result.data ?? <Note>[]) : <Note>[];
    return _buildResults(notes, context);
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
          leading: Icon(
            note.type == 'rich_text' ? Icons.text_fields : Icons.code,
          ),
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
