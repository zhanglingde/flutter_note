// test/services/sync/asset_migration_service_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_migration_service.dart';
import 'package:note/models/note.dart';

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
  late AssetMigrationService migrator;
  late Directory tmpDir;
  late String appDocsPath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('migration_test_');
    appDocsPath = '${tmpDir.path}/appdocs';
    Directory(appDocsPath).createSync(recursive: true);
    storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = appDocsPath;
    await storage.init();
    repo = AssetRepository(storage);
    storage.setAssetRepository(repo);
    migrator = AssetMigrationService(repo: repo, storage: storage);
  });

  tearDown(() async {
    await storage.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('migrateIfNeeded skips when no legacy dirs exist', () async {
    await migrator.migrateIfNeeded();

    expect((await storage.getSyncState('migration_v2_done')).data, '1');
    expect((await storage.listSyncAssets()).data, isEmpty);
  });

  test('migrateIfNeeded copies images/{noteId}/ to sync-assets and rewrites content', () async {
    // 1. 构造 legacy images/n1/123.png
    final legacyDir = Directory('$appDocsPath/images/n1');
    legacyDir.createSync(recursive: true);
    final imgPath = '$appDocsPath/images/n1/123.png';
    File(imgPath).writeAsBytesSync([10, 20, 30]);

    // 2. 保存一篇引用该绝对路径的笔记
    final content = '{"insert":{"image":"$imgPath"}}{"insert":"\\n"}';
    await storage.saveNote(_note('n1', content));

    // 3. 跑迁移
    await migrator.migrateIfNeeded();

    // 4. 断言 sync-assets 生成
    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 1);
    final r = records.first;
    expect(r.ext, 'png');
    expect(r.syncStatus, SyncStatus.dirty);

    // 5. 笔记 content 改写为 asset://
    final updated = (await storage.loadNoteById('n1')).data!;
    expect(updated.content, contains('asset://${r.hash}.png'));
    expect(updated.content, isNot(contains(imgPath)));

    // 6. 本地 sync-assets 文件存在
    expect(File('${appDocsPath}/sync-assets/${r.hash}.png').existsSync(), isTrue);

    // 7. 完成标记写入
    expect((await storage.getSyncState('migration_v2_done')).data, '1');

    // 8. 旧目录被重命名为 _migrated_backup
    expect(Directory('$appDocsPath/images').existsSync(), isFalse);
    expect(Directory('$appDocsPath/images_migrated_backup').existsSync(), isTrue);
  });

  test('migrateIfNeeded is idempotent: running twice does not double-migrate', () async {
    final legacyDir = Directory('$appDocsPath/images/n1');
    legacyDir.createSync(recursive: true);
    final imgPath = '$appDocsPath/images/n1/123.png';
    File(imgPath).writeAsBytesSync([10, 20, 30]);
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"$imgPath"}}{"insert":"\\n"}'));

    await migrator.migrateIfNeeded();
    await migrator.migrateIfNeeded(); // 第二次应是 no-op

    expect((await storage.listSyncAssets()).data!.length, 1);
  });

  test('migrateIfNeeded handles videos and thumbnails', () async {
    final legacyVideoDir = Directory('$appDocsPath/videos/n1');
    legacyVideoDir.createSync(recursive: true);
    final videoPath = '$appDocsPath/videos/n1/abc.mp4';
    final thumbPath = '$appDocsPath/videos/n1/thumb_abc.jpg';
    File(videoPath).writeAsBytesSync([1, 2, 3, 4]);
    File(thumbPath).writeAsBytesSync([5, 6, 7]);

    await storage.saveNote(_note('n1',
        '{"insert":{"video":"{\\"source\\":\\"$videoPath\\",\\"thumbnail\\":\\"$thumbPath\\"}"}}{"insert":"\\n"}'));

    await migrator.migrateIfNeeded();

    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 2); // 视频本体 + 缩略图

    final updated = (await storage.loadNoteById('n1')).data!;
    expect(updated.content, isNot(contains(videoPath)));
    expect(updated.content, isNot(contains(thumbPath)));
    expect(updated.content, contains('asset://'));
  });

  test('migrateIfNeeded does not choke on note with missing file', () async {
    // 笔记引用了一个不存在的路径——迁移时跳过该引用，不崩
    final legacyDir = Directory('$appDocsPath/images/n1');
    legacyDir.createSync(recursive: true);
    final imgPath = '$appDocsPath/images/n1/123.png';
    File(imgPath).writeAsBytesSync([10, 20, 30]);
    final ghostPath = '$appDocsPath/images/n1/ghost.png'; // 不存在

    await storage.saveNote(_note('n1',
        '{"insert":{"image":"$imgPath"}},{"insert":{"image":"$ghostPath"}},{"insert":"\\n"}'));

    await migrator.migrateIfNeeded();

    // 仅有的真实文件被迁移
    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 1);
  });
}
