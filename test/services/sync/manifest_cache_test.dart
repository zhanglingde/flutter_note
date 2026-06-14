import 'package:flutter_test/flutter_test.dart';
import 'package:note/services/sync/manifest_cache.dart';

void main() {
  test('ManifestData round-trip JSON preserves all fields', () {
    final data = ManifestData(
      version: 1,
      generatedAt: DateTime.utc(2026, 6, 14, 10, 0, 0),
      notes: {
        'abc.json': ManifestEntry(
          etag: '"e1"',
          size: 100,
          hash: 'sha-abc',
          updatedAt: DateTime.utc(2026, 6, 14, 9, 0, 0),
        ),
      },
      assets: {
        'h1.png': ManifestAssetEntry(etag: '"e2"', size: 200, refCount: 3),
      },
    );
    final json = data.toJson();
    final restored = ManifestData.fromJson(json);

    expect(restored.version, 1);
    expect(restored.generatedAt, DateTime.utc(2026, 6, 14, 10, 0, 0));

    expect(restored.notes.length, 1);
    final note = restored.notes['abc.json']!;
    expect(note.etag, '"e1"');
    expect(note.size, 100);
    expect(note.hash, 'sha-abc');
    expect(note.updatedAt, DateTime.utc(2026, 6, 14, 9, 0, 0));

    expect(restored.assets.length, 1);
    final asset = restored.assets['h1.png']!;
    expect(asset.etag, '"e2"');
    expect(asset.size, 200);
    expect(asset.refCount, 3);
  });

  test('ManifestEntry.needsDownload returns true when etag differs', () {
    final remote = ManifestEntry(
      etag: '"new"',
      size: 10,
      hash: 'h',
      updatedAt: DateTime.now(),
    );
    expect(remote.needsDownload(localEtag: '"old"'), isTrue);
    expect(remote.needsDownload(localEtag: '"new"'), isFalse);
    expect(remote.needsDownload(localEtag: null), isTrue);
  });

  test('ManifestData.fromJson handles malformed input by returning empty', () {
    // 缺字段时不崩溃，返回空数据
    final restored = ManifestData.fromJson({});
    expect(restored.notes, isEmpty);
    expect(restored.assets, isEmpty);
  });

  test('ManifestData.decode handles null and empty body', () {
    expect(ManifestData.decode(null).notes, isEmpty);
    expect(ManifestData.decode('').notes, isEmpty);
  });

  test('ManifestData.decode falls back to empty on invalid JSON', () {
    expect(ManifestData.decode('not json').notes, isEmpty);
    expect(ManifestData.decode('{invalid').notes, isEmpty);
  });

  test('ManifestData.decode parses valid JSON', () {
    const body = '{"version":1,"generatedAt":"2026-06-14T10:00:00.000Z",'
        '"notes":{},"assets":{}}';
    final data = ManifestData.decode(body);
    expect(data.version, 1);
    expect(data.notes, isEmpty);
  });

  test('ManifestData.empty returns valid empty data', () {
    final data = ManifestData.empty();
    expect(data.version, 1);
    expect(data.notes, isEmpty);
    expect(data.assets, isEmpty);
  });
}
