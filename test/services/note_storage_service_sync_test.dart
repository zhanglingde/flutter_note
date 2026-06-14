import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:note/services/note_storage_service.dart';
import 'package:note/models/note.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// 为每个测试生成一个独立的临时 DB 目录，避免互相干扰、避免污染真实应用数据。
  Future<String> freshDbDir() async {
    final tempDir =
        await Directory.systemTemp.createTemp('note_sync_test_');
    return tempDir.path;
  }

  test('init creates notes table with sync columns', () async {
    final service = NoteStorageService()..dbPathOverride = await freshDbDir();
    await service.init();
    // 通过保存一个笔记并查回来，验证字段持久化
    final now = DateTime.now();
    final note = Note(
      id: 'sync-test-1',
      title: 'T',
      content: 'C',
      type: 'rich_text',
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.dirty,
      remoteEtag: '"e1"',
      localHash: 'hash1',
    );
    await service.saveNote(note);

    final loaded = (await service.loadNoteById(note.id)).data!;
    expect(loaded.syncStatus, SyncStatus.dirty);
    expect(loaded.remoteEtag, '"e1"');
    expect(loaded.localHash, 'hash1');

    await service.close();
  });

  test('loadAllNotesIncludingDeleted returns tombstones', () async {
    final service = NoteStorageService()..dbPathOverride = await freshDbDir();
    await service.init();
    final now = DateTime.now();
    final alive = Note(
      id: 'alive-1', title: 'a', content: '', type: 'rich_text',
      createdAt: now, updatedAt: now,
    );
    final dead = Note(
      id: 'dead-1', title: 'd', content: '', type: 'rich_text',
      createdAt: now, updatedAt: now,
      deletedAt: now, syncStatus: SyncStatus.dirty,
    );
    await service.saveNote(alive);
    await service.saveNote(dead);

    final all = (await service.loadAllNotesIncludingDeleted()).data!;
    expect(all.map((n) => n.id).toSet(), {'alive-1', 'dead-1'});

    await service.close();
  });

  test('sync_assets and sync_state tables exist', () async {
    final service = NoteStorageService()..dbPathOverride = await freshDbDir();
    await service.init();
    // upsert asset 应成功
    final upsertResult = await service.upsertSyncAsset(
      hash: 'h1', ext: 'png',
      localPath: '/tmp/x.png', syncStatus: SyncStatus.clean,
    );
    expect(upsertResult.success, isTrue);
    final assets = (await service.listSyncAssets()).data!;
    expect(assets.length, 1);
    expect(assets.first.hash, 'h1');

    // setSyncState / getSyncState
    final setStateResult =
        await service.setSyncState('lastSyncAt', '2026-06-14T00:00:00');
    expect(setStateResult.success, isTrue);
    final value = (await service.getSyncState('lastSyncAt')).data;
    expect(value, '2026-06-14T00:00:00');

    await service.close();
  });

  test('getSyncState returns null for missing key', () async {
    final service = NoteStorageService()..dbPathOverride = await freshDbDir();
    await service.init();
    final result = await service.getSyncState('nonexistent');
    expect(result.success, isTrue);
    expect(result.data, isNull);
    await service.close();
  });

  test('loadNotesBySyncStatus filters by status', () async {
    final service = NoteStorageService()..dbPathOverride = await freshDbDir();
    await service.init();
    final now = DateTime.now();
    // 注意：saveNote 现在会把 clean 笔记自动标记为 dirty（任务 14 行为变更）
    // 所以 clean-1 保存后实际是 dirty。改用 dirty 与 conflict 区分以测筛选。
    await service.saveNote(Note(
      id: 'dirty-1', title: 'd', content: '', type: 'rich_text',
      createdAt: now, updatedAt: now, syncStatus: SyncStatus.dirty,
    ));
    await service.saveNote(Note(
      id: 'conflict-1', title: 'c', content: '', type: 'rich_text',
      createdAt: now, updatedAt: now, syncStatus: SyncStatus.conflict,
    ));
    final dirtyResult = await service.loadNotesBySyncStatus(SyncStatus.dirty);
    expect(dirtyResult.success, isTrue);
    expect(dirtyResult.data!.map((n) => n.id).toList(), ['dirty-1']);
    final conflictResult =
        await service.loadNotesBySyncStatus(SyncStatus.conflict);
    expect(conflictResult.data!.map((n) => n.id).toList(), ['conflict-1']);
    await service.close();
  });

  // ==================== 任务 14: saveNote 自动标记 dirty ====================

  test('saveNote marks clean note as dirty for sync', () async {
    final service = NoteStorageService()..dbPathOverride = await freshDbDir();
    await service.init();
    final now = DateTime.now();
    final note = Note(
      id: 'auto-dirty-1',
      title: 'T',
      content: 'C',
      type: 'rich_text',
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.clean,
    );

    await service.saveNote(note);

    final loaded = (await service.loadNoteById(note.id)).data!;
    expect(loaded.syncStatus, SyncStatus.dirty,
        reason: 'clean 笔记保存后应自动标记为 dirty');
    await service.close();
  });

  test('saveNote preserves dirty status', () async {
    final service = NoteStorageService()..dbPathOverride = await freshDbDir();
    await service.init();
    final now = DateTime.now();
    final note = Note(
      id: 'keep-dirty-1',
      title: 'T',
      content: 'C',
      type: 'rich_text',
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.dirty,
    );

    await service.saveNote(note);

    final loaded = (await service.loadNoteById(note.id)).data!;
    expect(loaded.syncStatus, SyncStatus.dirty);
    await service.close();
  });

  test('saveNote preserves tombstone without marking dirty', () async {
    final service = NoteStorageService()..dbPathOverride = await freshDbDir();
    await service.init();
    final now = DateTime.now();
    final tombstone = Note(
      id: 'tomb-1',
      title: 'T',
      content: 'C',
      type: 'rich_text',
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.clean,
      deletedAt: now,
    );

    await service.saveNote(tombstone);

    final loaded = (await service.loadAllNotesIncludingDeleted()).data!
        .firstWhere((n) => n.id == 'tomb-1');
    expect(loaded.syncStatus, SyncStatus.clean,
        reason: '已删除的墓碑不应被改为 dirty（避免破坏墓碑状态）');
    expect(loaded.deletedAt, isNotNull);
    await service.close();
  });

  test('onUpgrade migrates v1 DB to v2 (adds sync columns + new tables)',
      () async {
    final dir = await freshDbDir();
    final dbPath = p.join(dir, 'notes.db');

    // 1) 先手工创建一个 v1 schema 的 DB（无 sync 列、无 sync_assets/sync_state）
    {
      final db = await openDatabase(dbPath, version: 1,
          onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '',
            content TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT 'rich_text',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_notes_updated_at ON notes (updated_at DESC)');
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        // 插入一条 v1 风格的笔记（没有 sync 列）
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('notes', {
          'id': 'legacy-1',
          'title': 'legacy',
          'content': 'old',
          'type': 'rich_text',
          'created_at': now,
          'updated_at': now,
        });
      });
      await db.close();
    }

    // 2) 用 NoteStorageService 打开同一个 DB，应触发 onUpgrade
    final service = NoteStorageService()..dbPathOverride = dir;
    await service.init();

    // 3) legacy 笔记应可加载，sync 字段为默认值
    final loaded = (await service.loadNoteById('legacy-1')).data!;
    expect(loaded.title, 'legacy');
    expect(loaded.syncStatus, SyncStatus.clean); // 默认值
    expect(loaded.remoteEtag, isNull);
    expect(loaded.localHash, isNull);
    expect(loaded.deletedAt, isNull);

    // 4) 新表应可用
    await service.upsertSyncAsset(
      hash: 'migrated-asset', ext: 'jpg',
      localPath: '/tmp/y.jpg', syncStatus: SyncStatus.clean,
    );
    expect((await service.listSyncAssets()).data!.length, 1);
    await service.setSyncState('k', 'v');
    expect((await service.getSyncState('k')).data, 'v');

    // 5) 可保存带 sync 字段的新笔记（证明新列存在）
    final now = DateTime.now();
    await service.saveNote(Note(
      id: 'new-1', title: 'n', content: '', type: 'rich_text',
      createdAt: now, updatedAt: now,
      syncStatus: SyncStatus.dirty, remoteEtag: '"e"', localHash: 'h',
    ));
    final newLoaded = (await service.loadNoteById('new-1')).data!;
    expect(newLoaded.syncStatus, SyncStatus.dirty);

    await service.close();
  });
}
