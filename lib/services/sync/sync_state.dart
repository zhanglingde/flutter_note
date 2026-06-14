import 'package:flutter/foundation.dart';

/// 同步状态徽章类型
enum SyncStatusType {
  /// 已同步（idle）
  idle,
  /// 同步中
  syncing,
  /// 有未推送的本地变更
  dirty,
  /// 有未处理冲突
  conflict,
  /// 离线
  offline,
  /// 出错
  error,
}

/// 同步状态管理（UI 监听用）
class SyncStateManager extends ChangeNotifier {
  SyncStatusType _status = SyncStatusType.idle;
  DateTime? _lastSyncAt;
  int _pendingDirtyCount = 0;
  int _conflictCount = 0;
  String? _errorMessage;

  SyncStatusType get status => _status;
  DateTime? get lastSyncAt => _lastSyncAt;
  int get pendingDirtyCount => _pendingDirtyCount;
  int get conflictCount => _conflictCount;
  String? get errorMessage => _errorMessage;

  void markSyncing() {
    _status = SyncStatusType.syncing;
    _errorMessage = null;
    notifyListeners();
  }

  void markSuccess() {
    _lastSyncAt = DateTime.now();
    _errorMessage = null;
    _status = _computeIdleStatus();
    notifyListeners();
  }

  void markError(String message) {
    _errorMessage = message;
    _status = SyncStatusType.error;
    notifyListeners();
  }

  void markConflict({required int conflictCount}) {
    _conflictCount = conflictCount;
    _status = SyncStatusType.conflict;
    notifyListeners();
  }

  void setOffline() {
    _status = SyncStatusType.offline;
    notifyListeners();
  }

  void setIdle() {
    _status = _computeIdleStatus();
    notifyListeners();
  }

  void setDirtyCount(int count) {
    _pendingDirtyCount = count;
    // 冲突优先级 > dirty
    if (_status != SyncStatusType.conflict &&
        _status != SyncStatusType.syncing &&
        _status != SyncStatusType.error) {
      _status = count > 0 ? SyncStatusType.dirty : SyncStatusType.idle;
    }
    notifyListeners();
  }

  SyncStatusType _computeIdleStatus() {
    if (_conflictCount > 0) return SyncStatusType.conflict;
    if (_pendingDirtyCount > 0) return SyncStatusType.dirty;
    return SyncStatusType.idle;
  }
}
