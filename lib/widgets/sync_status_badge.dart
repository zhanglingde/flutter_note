import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sync/sync_state.dart';

/// AppBar 右侧的同步状态徽章
class SyncStatusBadge extends StatelessWidget {
  final VoidCallback? onTap;
  const SyncStatusBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.read<SyncStateManager>(),
      builder: (context, _) {
        final state = context.read<SyncStateManager>();
        return IconButton(
          icon: _buildIcon(state),
          tooltip: _buildTooltip(state),
          onPressed: onTap,
        );
      },
    );
  }

  Widget _buildIcon(SyncStateManager state) {
    switch (state.status) {
      case SyncStatusType.idle:
        return const Icon(Icons.cloud_done, color: Colors.grey);
      case SyncStatusType.syncing:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncStatusType.dirty:
        return const Icon(Icons.cloud_upload, color: Colors.orange);
      case SyncStatusType.conflict:
        return const Icon(Icons.warning, color: Colors.red);
      case SyncStatusType.offline:
        return const Icon(Icons.cloud_off, color: Colors.grey);
      case SyncStatusType.error:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  String _buildTooltip(SyncStateManager state) {
    switch (state.status) {
      case SyncStatusType.idle:
        final t = state.lastSyncAt;
        return t == null ? '尚未同步' : '已同步 · ${_formatTime(t)}';
      case SyncStatusType.syncing:
        return '同步中...';
      case SyncStatusType.dirty:
        return '${state.pendingDirtyCount} 篇待同步';
      case SyncStatusType.conflict:
        return '${state.conflictCount} 个冲突待处理';
      case SyncStatusType.offline:
        return '离线';
      case SyncStatusType.error:
        return state.errorMessage ?? '同步出错';
    }
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
