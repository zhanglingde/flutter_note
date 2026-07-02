import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_resolver.dart';

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late NoteStorageService storage;
  late AssetRepository repo;
  late AssetResolver resolver;
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('asset_resolver_test_');
    storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    repo = AssetRepository(storage);
    resolver = AssetResolver(storage);
  });

  tearDown(() async {
    await storage.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('resolveLocalPath returns path when asset:// and file exists', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    final path = await resolver.resolveLocalPath(ref.uri);
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
  });

  test('resolveLocalPath returns null when file missing', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    File('${tmpDir.path}/appdocs/sync-assets/${ref.hash}.png').deleteSync();
    expect(await resolver.resolveLocalPath(ref.uri), isNull);
  });

  test('resolveLocalPath returns null when hash unknown', () async {
    expect(await resolver.resolveLocalPath('asset://unknown.png'), isNull);
  });

  test('resolveLocalPath passes through non-asset:// source unchanged', () async {
    expect(await resolver.resolveLocalPath('https://x.com/y.png'), 'https://x.com/y.png');
    expect(await resolver.resolveLocalPath('/data/user/0/x.png'), '/data/user/0/x.png');
    expect(await resolver.resolveLocalPath(r'C:\x\y.png'), r'C:\x\y.png');
  });

  test('resolveLocalPath handles null and empty', () async {
    expect(await resolver.resolveLocalPath(null), isNull);
    expect(await resolver.resolveLocalPath(''), isNull);
  });
}
