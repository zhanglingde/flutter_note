// test/services/sync/asset_sync_integration_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_resolver.dart';
import 'package:note/services/sync/local_backend.dart';
import 'package:note/services/sync/sync_backend.dart';
import 'package:note/services/sync/sync_service.dart';
import 'package:note/services/sync/sync_state.dart';
import 'package:note/models/note.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmpDirA;
  late Directory tmpDirB;
  late LocalBackend backend; // 共享远端

  setUp(() async {
    tmpDirA = await Directory.systemTemp.createTemp('integration_A_');
    tmpDirB = await Directory.systemTemp.createTemp('integration_B_');
    backend = LocalBackend();
    await backend.authenticate(const Credentials(username: 'u', password: 'p'));
  });

  tearDown(() async {
    if (tmpDirA.existsSync()) await tmpDirA.delete(recursive: true);
    if (tmpDirB.existsSync()) await tmpDirB.delete(recursive: true);
  });

  Future<SyncService> makeDevice(Directory tmpDir, String label) async {
    final storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    final assetRepo = AssetRepository(storage);
    storage.setAssetRepository(assetRepo);
    final state = SyncStateManager();
    final sync = SyncService(
      storage: storage,
      backend: backend,
      state: state,
      rootPath: '/notes-app/',
    );
    return sync;
  }

  test('A saves note with image → sync → B pulls → B can resolve asset', () async {
    // === 设备 A ===
    final syncA = await makeDevice(tmpDirA, 'A');
    final storageA = syncA.storage;
    final repoA = AssetRepository(storageA);

    // A 保存一张图片
    final ref = await repoA.save(Uint8List.fromList([1, 2, 3, 4, 5]), 'png');

    // A 保存一篇引用该图片的笔记
    final note = Note(
      id: 'note-cross-device',
      title: 'Cross',
      content: '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}',
      type: 'rich_text',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.dirty,
    );
    await storageA.saveNote(note);

    // A 同步
    await syncA.syncOnce();

    // === 远端验证 ===
    expect(await backend.exists('/notes-app/notes/note-cross-device.json'), isTrue);
    expect(await backend.exists('/notes-app/assets/${ref.hash}.png'), isTrue);

    // === 设备 B（全新）===
    final syncB = await makeDevice(tmpDirB, 'B');
    final storageB = syncB.storage;

    // B 同步
    await syncB.syncOnce();

    // B 应有这篇笔记
    final loaded = (await storageB.loadNoteById('note-cross-device')).data!;
    expect(loaded.title, 'Cross');
    expect(loaded.content, contains('asset://${ref.hash}.png'));

    // B 的 sync_assets 表应有该 hash
    final records = (await storageB.listSyncAssets()).data!;
    final r = records.where((x) => x.hash == ref.hash).toList();
    expect(r, isNotEmpty);
    expect(r.first.syncStatus, SyncStatus.clean);

    // B 的 AssetResolver 能解析到本地路径
    final resolverB = AssetResolver(storageB);
    final localPath = await resolverB.resolveLocalPath(ref.uri);
    expect(localPath, isNotNull);
    expect(File(localPath!).existsSync(), isTrue);
    expect(await File(localPath).readAsBytes(), [1, 2, 3, 4, 5]);

    // 清理
    await storageA.close();
    await storageB.close();
  });

  test('A edits note removing image → sync → B syncs → A refcount drops to 0', () async {
    // 验证：A 设备编辑笔记移除 asset 引用后，saveNote 的 diff 逻辑会让
    // sync_assets 表 ref_count 归 0；远端笔记更新被 B 拉到后，B 的笔记
    // 内容中也不再有 asset:// 引用。
    //
    // 注：B 设备的 sync_assets 表 ref_count 不在断言范围——saveNoteFromSync
    // 路径不维护引用计数（仅 saveNote 走 diff）。
    final syncA = await makeDevice(tmpDirA, 'A');
    final storageA = syncA.storage;
    final repoA = AssetRepository(storageA);

    final ref = await repoA.save(Uint8List.fromList([1, 2, 3]), 'png');
    final note = Note(
      id: 'note-edit-asset',
      title: 'Edit',
      content: '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}',
      type: 'rich_text',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.dirty,
    );
    await storageA.saveNote(note);
    await syncA.syncOnce();

    // A 编辑笔记：移除图片引用
    final updated = note.copyWith(
      content: '{"insert":"no image\\n"}',
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.dirty,
    );
    await storageA.saveNote(updated);
    await syncA.syncOnce();

    // A 的 refcount 应为 0、status dirty（等待 cleanup 处理）
    final recordsA = (await storageA.listSyncAssets()).data!;
    final rA = recordsA.firstWhere((x) => x.hash == ref.hash);
    expect(rA.refCount, 0);
    expect(rA.syncStatus, SyncStatus.dirty);

    // B 同步：拉到更新后的笔记
    final syncB = await makeDevice(tmpDirB, 'B');
    final storageB = syncB.storage;
    await syncB.syncOnce();

    final bNote = (await storageB.loadNoteById('note-edit-asset')).data!;
    expect(bNote.content, isNot(contains('asset://')));

    await storageA.close();
    await storageB.close();
  });
}
