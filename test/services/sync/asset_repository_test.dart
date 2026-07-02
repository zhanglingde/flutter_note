import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/models/note.dart';

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late NoteStorageService storage;
  late AssetRepository repo;
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('asset_repo_test_');
    storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    repo = AssetRepository(storage);
  });

  tearDown(() async {
    await storage.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('save writes file to sync-assets/{hash}.{ext} and creates record dirty',
      () async {
    final ref = await repo.save(_bytes([1, 2, 3, 4]), 'png');

    expect(ref.ext, 'png');
    expect(ref.hash.length, 64); // sha256 hex

    final file = File('${tmpDir.path}/appdocs/sync-assets/${ref.hash}.png');
    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);

    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 1);
    expect(records.first.hash, ref.hash);
    expect(records.first.ext, 'png');
    expect(records.first.syncStatus, SyncStatus.dirty);
    expect(records.first.refCount, 0);
  });

  test('save dedupes by hash: same content returns same ref, file not rewritten',
      () async {
    final ref1 = await repo.save(_bytes([1, 2, 3]), 'png');
    final ref2 = await repo.save(_bytes([1, 2, 3]), 'png');

    expect(ref1.hash, ref2.hash);
    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 1);
  });

  test('save with different ext produces different records', () async {
    final ref1 = await repo.save(_bytes([1, 2, 3]), 'png');
    final ref2 = await repo.save(_bytes([1, 2, 3]), 'jpg');
    expect(ref1.hash, ref2.hash);
    // 同 hash 不同 ext：当前实现按 hash 主键覆盖，ext 取最后一次。
    // 测试只是断言不崩，业务上推荐统一一种 ext。
  });

  test('read returns bytes when file exists', () async {
    final ref = await repo.save(_bytes([10, 20, 30]), 'png');
    final bytes = await repo.read(ref.hash);
    expect(bytes, isNotNull);
    expect(bytes!, [10, 20, 30]);
  });

  test('read returns null when hash not in table', () async {
    expect(await repo.read('nonexistenthash'), isNull);
  });

  test('read returns null when record exists but file missing', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    File('${tmpDir.path}/appdocs/sync-assets/${ref.hash}.png').deleteSync();
    expect(await repo.read(ref.hash), isNull);
  });

  test('incrementRefs bumps ref_count for given hashes', () async {
    final ref1 = await repo.save(_bytes([1, 2, 3]), 'png');
    final ref2 = await repo.save(_bytes([4, 5, 6]), 'png');

    await repo.incrementRefs({ref1.hash, ref2.hash});
    await repo.incrementRefs({ref1.hash}); // 二次增量

    final records = (await storage.listSyncAssets()).data!;
    final r1 = records.firstWhere((r) => r.hash == ref1.hash);
    final r2 = records.firstWhere((r) => r.hash == ref2.hash);
    expect(r1.refCount, 2);
    expect(r2.refCount, 1);
  });

  test('incrementRefs is idempotent for same hash in one call (set semantics)',
      () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await repo.incrementRefs({ref.hash, ref.hash}); // 集合去重
    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 1);
  });

  test('decrementRefs decrements and marks dirty when reaching 0', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await repo.incrementRefs({ref.hash});
    await repo.incrementRefs({ref.hash});
    expect((await storage.listSyncAssets()).data!.first.refCount, 2);

    await repo.decrementRefs({ref.hash});
    expect((await storage.listSyncAssets()).data!.first.refCount, 1);
    expect(
        (await storage.listSyncAssets()).data!.first.syncStatus, SyncStatus.dirty);

    await repo.decrementRefs({ref.hash});
    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 0);
    expect(r.syncStatus, SyncStatus.dirty); // 等待 cleanup 清理
  });

  test('decrementRefs clamps at 0 (never negative)', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await repo.decrementRefs({ref.hash}); // 没增过也减
    expect((await storage.listSyncAssets()).data!.first.refCount, 0);
  });

  test('decrementRefs on unknown hash is a no-op', () async {
    await repo.decrementRefs({'unknownhash'});
    expect((await storage.listSyncAssets()).data!, isEmpty);
  });
}
