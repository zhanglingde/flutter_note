import 'package:flutter/material.dart';

import '../services/sync/sync_backend.dart';
import '../services/sync/sync_service.dart';

/// 冲突副本查看页
///
/// 列出远端 `__conflict-{ts}.json` 文件，用户可下载到本地或删除。
/// 由路由（任务 14 集成）打开，调用方传入 [SyncService] 实例。
class ConflictViewerScreen extends StatefulWidget {
  final SyncService syncService;
  const ConflictViewerScreen({super.key, required this.syncService});

  @override
  State<ConflictViewerScreen> createState() => _ConflictViewerScreenState();
}

class _ConflictViewerScreenState extends State<ConflictViewerScreen> {
  List<RemoteFile> _conflicts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final files = await widget.syncService.listConflictFiles();
      if (mounted) {
        setState(() => _conflicts = files);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('冲突副本')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conflicts.isEmpty
              ? const Center(child: Text('暂无冲突副本'))
              : ListView.separated(
                  itemCount: _conflicts.length,
                  separatorBuilder: (_, _) => const Divider(height: 0),
                  itemBuilder: (_, i) {
                    final file = _conflicts[i];
                    return ListTile(
                      leading: const Icon(Icons.warning_amber,
                          color: Colors.orange),
                      title: Text(file.path.split('/').last),
                      subtitle: Text(
                        '大小 ${file.size} B · 修改于 ${file.lastModified.toLocal()}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => _handleAction(file, v),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'download', child: Text('下载到本地')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('删除副本')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _handleAction(RemoteFile file, String action) async {
    try {
      switch (action) {
        case 'download':
          await widget.syncService.downloadConflictToDesktop(file);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已下载')),
            );
          }
          break;
        case 'delete':
          await widget.syncService.deleteConflictFile(file);
          await _load();
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$e')),
        );
      }
    }
  }
}
