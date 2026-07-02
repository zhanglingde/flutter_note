import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_resolver.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('AssetResolver behavior matches embed builder expectations', () async {
    final tmpDir = await Directory.systemTemp.createTemp('resolver_test_');
    final storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    final repo = AssetRepository(storage);
    final resolver = AssetResolver(storage);
    addTearDown(() async {
      await storage.close();
      if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
    });

    final ref = await repo.save(Uint8List.fromList([1, 2, 3]), 'png');
    expect(await resolver.resolveLocalPath(ref.uri), isNotNull);

    File('${tmpDir.path}/appdocs/sync-assets/${ref.hash}.png').deleteSync();
    expect(await resolver.resolveLocalPath(ref.uri), isNull);

    expect(
      await resolver.resolveLocalPath('https://example.com/x.png'),
      'https://example.com/x.png',
    );
  });
}
