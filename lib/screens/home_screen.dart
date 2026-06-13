import 'dart:convert';
import 'dart:io';
import 'dart:math' show min, max;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/tab_state.dart';
import '../services/note_storage_service.dart';
import '../services/image_storage_service.dart';
import '../services/video_storage_service.dart';
import '../utils/delta_to_markdown.dart';
import '../utils/media_thumbnail.dart';
import '../widgets/rich_text_editor.dart';

enum NoteListViewMode { list, waterfall }

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
  NoteListViewMode _viewMode = NoteListViewMode.list;
  double _sidebarWidth = 320;

  /// 标签页管理
  final List<TabState> _tabs = [];
  String? _activeTabId;

  static const int _maxTabs = 20;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    _loadNotes();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('note_list_view_mode');
    if (saved == 'waterfall' && mounted) {
      setState(() => _viewMode = NoteListViewMode.waterfall);
    }
  }

  Future<void> _setViewMode(NoteListViewMode mode) async {
    setState(() => _viewMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'note_list_view_mode',
      mode == NoteListViewMode.waterfall ? 'waterfall' : 'list',
    );
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

  // ==================== 标签页管理 ====================

  /// 打开笔记（如果已打开则切换，否则新建标签页）
  void _openTab(Note note) {
    final existingIndex = _tabs.indexWhere((t) => t.id == note.id);
    if (existingIndex >= 0) {
      // 已打开 -> 切换并更新访问时间
      setState(() {
        _activeTabId = note.id;
        _tabs[existingIndex] = _tabs[existingIndex]
            .copyWith(lastAccessedAt: DateTime.now());
      });
    } else {
      // 未打开 -> 新建标签页
      if (_tabs.length >= _maxTabs) {
        _evictOldestTab();
      }
      setState(() {
        _tabs.add(TabState(note: note, key: GlobalKey()));
        _activeTabId = note.id;
      });
    }
  }

  /// 关闭标签页
  void _closeTab(String tabId) async {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return;

    // 先保存
    final tab = _tabs[index];
    widget.storageService.scheduleAutoSave(tab.note);
    await widget.storageService.flushAutoSave();

    setState(() {
      _tabs.removeAt(index);
      if (_activeTabId == tabId) {
        // 切换到相邻标签页
        if (_tabs.isEmpty) {
          _activeTabId = null;
        } else if (index < _tabs.length) {
          _activeTabId = _tabs[index].id;
        } else {
          _activeTabId = _tabs.last.id;
        }
      }
    });
  }

  /// 关闭标签页（不保存，用于删除笔记时先关闭标签页）
  void _closeTabWithoutSave(String tabId) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return;
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabId == tabId) {
        if (_tabs.isEmpty) {
          _activeTabId = null;
        } else if (index < _tabs.length) {
          _activeTabId = _tabs[index].id;
        } else {
          _activeTabId = _tabs.last.id;
        }
      }
    });
  }

  /// LRU 淘汰最旧的标签页
  void _evictOldestTab() {
    if (_tabs.isEmpty) return;
    TabState oldest = _tabs.first;
    for (final tab in _tabs) {
      if (tab.lastAccessedAt.isBefore(oldest.lastAccessedAt)) {
        oldest = tab;
      }
    }
    _closeTab(oldest.id);
  }

  void _onTabContentChanged(String tabId, String content) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return;

    final title = _extractTitle(content);
    debugPrint('_onTabContentChanged: tabId=$tabId, title=$title, content length=${content.length}, content preview=${content.length > 200 ? content.substring(0, 200) : content}');
    final updatedNote = _tabs[index].note.copyWith(
      content: content,
      title: title,
      updatedAt: DateTime.now(),
    );
    setState(() {
      _tabs[index] = _tabs[index].copyWith(note: updatedNote);
    });
    _updateNoteInList(updatedNote);
    widget.storageService.scheduleAutoSave(updatedNote);
  }

  void _reorderTabs(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final tab = _tabs.removeAt(oldIndex);
      _tabs.insert(newIndex, tab);
    });
  }

  // ==================== 笔记操作 ====================

  Future<void> _clipToNewNote(String deltaJson) async {
    final now = DateTime.now();
    final title = _extractTitle(deltaJson);
    debugPrint('_clipToNewNote: id=${now.millisecondsSinceEpoch}, title=$title, content length=${deltaJson.length}');
    final note = Note(
      id: now.millisecondsSinceEpoch.toString(),
      title: title,
      content: deltaJson,
      type: 'rich_text',
      createdAt: now,
      updatedAt: now,
    );

    final result = await widget.storageService.saveNote(note);
    debugPrint('_clipToNewNote: saveNote result=${result.success}');
    if (result.success && mounted) {
      _loadNotes();
      _openTab(note);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '创建笔记失败')),
      );
    }
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
        _openTab(note);
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
      _openTab(note);
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

    if (confirmed == true) {
      final result = await widget.storageService.deleteNote(note.id);
      if (result.success) {
        await ImageStorageService().deleteImagesForNote(note.id);
        await VideoStorageService().deleteVideosForNote(note.id);
        if (_tabs.any((t) => t.id == note.id)) {
          _closeTabWithoutSave(note.id);
        }
        _loadNotes();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.error ?? '删除笔记失败')));
      }
    }
  }

  // ==================== 构建 UI ====================

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout();
  }

  /// 桌面端：左右两栏布局 + 标签页
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // 左侧：笔记列表面板（宽度可拖动）
          SizedBox(
            width: _sidebarWidth,
            child: _buildNoteListPanel(),
          ),
          // 可拖动分隔线
          _buildSidebarResizer(),
          // 右侧：标签栏 + 编辑器面板
          Expanded(
            child: _tabs.isEmpty
                ? _buildEmptyEditorPanel()
                : _buildEditorPanelWithTabs(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 侧边栏可拖动分隔线
  Widget _buildSidebarResizer() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _sidebarWidth =
                (_sidebarWidth + details.delta.dx).clamp(200.0, 500.0);
          });
        },
        child: Container(
          width: 6,
          color: Theme.of(context).dividerColor,
        ),
      ),
    );
  }

  /// 标签栏 + 编辑器面板
  Widget _buildEditorPanelWithTabs() {
    return Column(
      children: [
        // 标签栏
        _buildTabBar(),
        // 编辑器（Offstage 包裹所有标签页的编辑器）
        Expanded(
          child: Stack(
            children: _tabs.map((tab) {
              final isActive = tab.id == _activeTabId;
              return Offstage(
                offstage: !isActive,
                child: KeyedSubtree(
                  key: tab.key,
                  child: RichTextEditor(
                    initialContent: tab.note.content,
                    onContentChanged: (content) =>
                        _onTabContentChanged(tab.id, content),
                    noteId: tab.note.id,
                    onClipToNewNote: (deltaJson) => _clipToNewNote(deltaJson),
                    actions: [
                      PopupMenuButton<String>(
                        onSelected: (action) =>
                            _handleEditorAction(action, tab.note),
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
                            value: 'copyMarkdown',
                            child: ListTile(
                              leading: Icon(Icons.data_object),
                              title: Text('复制为 Markdown'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete, color: Colors.red),
                              title: Text('删除',
                                  style: TextStyle(color: Colors.red)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 标签栏
  Widget _buildTabBar() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFF8F8F8),
            width: 1,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          final isActive = tab.id == _activeTabId;
          return _buildTabItem(tab, isActive, index);
        },
      ),
    );
  }

  Widget _buildTabItem(TabState tab, bool isActive, int index) {
    final title = _extractTitle(tab.note.content);
    final displayTitle = title.isEmpty ? '无标题' : title;

    return DragTarget<int>(
      onAcceptWithDetails: (details) {
        _reorderTabs(details.data, index);
      },
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            elevation: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Listener(
              onPointerDown: (event) {
                // 中键点击关闭标签页
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons & kMiddleMouseButton != 0) {
                  _closeTab(tab.id);
                }
              },
              child: InkWell(
                onTap: () {
                  setState(() {
                    _activeTabId = tab.id;
                    final i = _tabs.indexWhere((t) => t.id == tab.id);
                    if (i >= 0) {
                      _tabs[i] =
                          _tabs[i].copyWith(lastAccessedAt: DateTime.now());
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  constraints:
                      const BoxConstraints(minWidth: 100, maxWidth: 180),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.surface
                        : Colors.transparent,
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          padding: EdgeInsets.zero,
                          onPressed: () => _closeTab(tab.id),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
            leading: PopupMenuButton<NoteListViewMode>(
              icon: Icon(
                _viewMode == NoteListViewMode.list
                    ? Icons.view_list
                    : Icons.grid_view,
              ),
              onSelected: _setViewMode,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: NoteListViewMode.list,
                  child: Row(
                    children: [
                      const Icon(Icons.view_list, size: 18),
                      const SizedBox(width: 8),
                      const Text('列表视图'),
                      if (_viewMode == NoteListViewMode.list) ...[
                        const Spacer(),
                        const Icon(Icons.check, size: 18),
                      ],
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: NoteListViewMode.waterfall,
                  child: Row(
                    children: [
                      const Icon(Icons.grid_view, size: 18),
                      const SizedBox(width: 8),
                      const Text('瀑布流视图'),
                      if (_viewMode == NoteListViewMode.waterfall) ...[
                        const Spacer(),
                        const Icon(Icons.check, size: 18),
                      ],
                    ],
                  ),
                ),
              ],
            ),
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

    if (_viewMode == NoteListViewMode.waterfall) {
      return RefreshIndicator(
        onRefresh: _loadNotes,
        child: _buildWaterfallView(notes),
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
    final title = _extractTitle(note.content);
    final preview = _getPreview(note.content);
    final isSelected = _tabs.any((t) => t.id == note.id && t.id == _activeTabId);
    final media = extractFirstMedia(note.content);

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
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3)
            : null,
        child: ListTile(
          selected: isSelected,
          leading: media != null ? _buildListThumbnail(media) : null,
          title: Text(
            title.isEmpty ? '无标题' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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

  Widget _buildListThumbnail(MediaInfo media) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 48,
        child: media.isVideo
            ? (media.thumbnail != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(File(media.thumbnail!), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Center(child: Icon(Icons.play_circle_filled, size: 24)))),
                      const Center(child: Icon(Icons.play_circle_filled, size: 24, color: Colors.white70)),
                    ],
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: Icon(Icons.play_circle_filled, size: 24),
                    ),
                  ))
            : media.isNetwork
                ? Image.network(media.source, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
                : Image.file(File(media.source), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
      ),
    );
  }

  Widget _buildWaterfallThumbnail(MediaInfo media) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 120),
        child: media.isVideo
            ? (media.thumbnail != null
                ? Stack(
                    fit: StackFit.passthrough,
                    children: [
                      Image.file(File(media.thumbnail!), fit: BoxFit.cover, width: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                              height: 80,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Center(child: Icon(Icons.play_circle_filled, size: 36)))),
                      Positioned.fill(
                        child: Center(child: Icon(Icons.play_circle_filled, size: 36, color: Colors.white70)),
                      ),
                    ],
                  )
                : Container(
                    height: 80,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: Icon(Icons.play_circle_filled, size: 36),
                    ),
                  ))
            : media.isNetwork
                ? Image.network(media.source, fit: BoxFit.cover, width: double.infinity,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink())
                : Image.file(File(media.source), fit: BoxFit.cover, width: double.infinity,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      ),
    );
  }

  Widget _buildWaterfallView(List<Note> notes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据面板宽度动态计算列数：1-3 列
        // 每列按 150px 阈值计算，最窄 1 列，最宽 3 列
        final crossAxisCount = min(
          3,
          max(1, (constraints.maxWidth / 150).floor()),
        );
        return MasonryGridView.builder(
          itemCount: notes.length,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
          ),
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            return _buildWaterfallCard(notes[index]);
          },
        );
      },
    );
  }

  Widget _buildWaterfallCard(Note note) {
    final title = _extractTitle(note.content);
    final preview = _getPreview(note.content);
    final isSelected = _tabs.any((t) => t.id == note.id && t.id == _activeTabId);
    final media = extractFirstMedia(note.content);

    return GestureDetector(
      onTap: () => _openNote(note),
      onSecondaryTap: () => _deleteNote(note),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (media != null) _buildWaterfallThumbnail(media),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? '无标题' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                    ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatDate(note.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => _deleteNote(note),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
        ),
      ),
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

  void _handleEditorAction(String action, Note note) async {
    switch (action) {
      case 'duplicate':
        final duplicatedNote = note.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '${note.title} (副本)',
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
      case 'copyMarkdown':
        final markdown = deltaToMarkdown(note.content);
        await Clipboard.setData(ClipboardData(text: markdown));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已复制为 Markdown')),
          );
        }
        break;
      case 'delete':
        await _deleteNote(note);
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
      final lines = buffer.toString().split('\n');
      // 跳过第一段（标题已显示），从第二段开始
      int start = 0;
      bool foundFirst = false;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].trim().isNotEmpty) {
          if (!foundFirst) {
            foundFirst = true;
            start = i + 1;
          }
        }
      }
      final remaining = lines.sublist(start).join(' ').trim();
      return remaining.isEmpty
          ? ''
          : (remaining.length > 100 ? '${remaining.substring(0, 100)}...' : remaining);
    } catch (e) {
      return content.length > 100
          ? '${content.substring(0, 100)}...'
          : content;
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

/// 从富文本内容中提取第一个非空行作为标题
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

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _onContentChanged(String content) {
    final title = _extractTitle(content);
    setState(() {
      _currentNote = _currentNote.copyWith(
        content: content,
        title: title,
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
          title: Text(
            _currentNote.title.isEmpty ? '无标题' : _currentNote.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'copyMarkdown':
                    final markdown = deltaToMarkdown(_currentNote.content);
                    await Clipboard.setData(ClipboardData(text: markdown));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制为 Markdown')),
                      );
                    }
                    break;
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
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      final result = await widget.storageService
                          .deleteNote(_currentNote.id);
                      if (result.success) {
                        await ImageStorageService()
                            .deleteImagesForNote(_currentNote.id);
                        await VideoStorageService()
                            .deleteVideosForNote(_currentNote.id);
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
                  value: 'copyMarkdown',
                  child: ListTile(
                    leading: Icon(Icons.data_object),
                    title: Text('复制为 Markdown'),
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
                  builder: (context) => _EditorScreenWrapper(
                    note: note,
                    storageService: widget.storageService,
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
