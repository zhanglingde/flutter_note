import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/models/note.dart';

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

Note _note(String id, String content) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: 'T',
    content: content,
    type: 'rich_text',
    createdAt: now,
    updatedAt: now,
    syncStatus: SyncStatus.dirty,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late NoteStorageService storage;
  late AssetRepository repo;
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('note_refcount_test_');
    storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    repo = AssetRepository(storage);
    storage.setAssetRepository(repo);
  });

  tearDown(() async {
    await storage.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('saveNote increments refs for new asset hashes in content', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    final content =
        '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}';
    await storage.saveNote(_note('n1', content));

    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 1);
  });

  test('saveNote diff: removing asset from content decrements old hash', () async {
    final ref1 = await repo.save(_bytes([1, 2, 3]), 'png');
    final ref2 = await repo.save(_bytes([4, 5, 6]), 'png');

    // 第一次保存：包含 ref1 和 ref2
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"${ref1.uri}"}}{"insert":{"image":"${ref2.uri}"}}{"insert":"\\n"}'));

    // 第二次保存：只剩 ref2
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"${ref2.uri}"}}{"insert":"\\n"}'));

    final records = (await storage.listSyncAssets()).data!;
    final r1 = records.firstWhere((r) => r.hash == ref1.hash);
    final r2 = records.firstWhere((r) => r.hash == ref2.hash);
    expect(r1.refCount, 0);
    expect(r1.syncStatus, SyncStatus.dirty);
    expect(r2.refCount, 1);
  });

  test('saveNote diff: same hash in multiple notes accumulates', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}'));
    await storage.saveNote(_note('n2',
        '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}'));

    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 2);
  });

  test('deleteNote decrements all asset hashes from content', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}'));

    expect((await storage.listSyncAssets()).data!.first.refCount, 1);

    await storage.deleteNote('n1');

    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 0);
    expect(r.syncStatus, SyncStatus.dirty);
  });

  test('saveNote without assetRepo injected skips refcount maintenance', () async {
    final rawStorage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/raw.db';
    await rawStorage.init();
    // 不调 setAssetRepository
    addTearDown(() async => await rawStorage.close());

    await rawStorage.saveNote(_note('n1', '{"insert":"hello\\n"}'));
    // 不应崩溃；sync_assets 表为空
    expect((await rawStorage.listSyncAssets()).data!, isEmpty);
  });
}
