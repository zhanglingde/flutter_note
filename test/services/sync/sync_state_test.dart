import 'package:flutter_test/flutter_test.dart';
import 'package:note/services/sync/sync_state.dart';

void main() {
  test('initial state is idle with no last sync', () {
    final state = SyncStateManager();
    expect(state.status, SyncStatusType.idle);
    expect(state.lastSyncAt, isNull);
    expect(state.pendingDirtyCount, 0);
    expect(state.conflictCount, 0);
    expect(state.errorMessage, isNull);
  });

  test('transition to syncing notifies listeners', () async {
    final state = SyncStateManager();
    var notified = 0;
    state.addListener(() => notified++);

    state.markSyncing();
    expect(state.status, SyncStatusType.syncing);
    expect(notified, 1);
  });

  test('markSuccess updates lastSyncAt and clears error', () {
    final state = SyncStateManager()
      ..markError('boom')
      ..markSuccess();
    expect(state.status, SyncStatusType.idle);
    expect(state.lastSyncAt, isNotNull);
    expect(state.errorMessage, isNull);
  });

  test('markConflict sets status conflict and counts', () {
    final state = SyncStateManager()
      ..markConflict(conflictCount: 2);
    expect(state.status, SyncStatusType.conflict);
    expect(state.conflictCount, 2);
  });

  test('setOffline flips status', () {
    final state = SyncStateManager()..setOffline();
    expect(state.status, SyncStatusType.offline);
    state.setIdle();
    expect(state.status, SyncStatusType.idle);
  });

  test('setDirtyCount keeps conflict status if set', () {
    final state = SyncStateManager()
      ..markConflict(conflictCount: 1)
      ..setDirtyCount(5);
    // 冲突优先级高于 dirty
    expect(state.status, SyncStatusType.conflict);
  });
}
