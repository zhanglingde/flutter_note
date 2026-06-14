import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:note/services/sync/local_backend.dart';
import 'package:note/services/sync/sync_backend.dart';

void main() {
  late LocalBackend backend;

  setUp(() {
    backend = LocalBackend();
  });

  test('authenticate accepts any credentials', () async {
    await backend.authenticate(
      const Credentials(username: 'u', password: 'p'),
    );
  });

  test('mkcol creates directory entry; second mkcol is no-op', () async {
    await backend.mkcol('/notes/');
    await backend.mkcol('/notes/'); // 不抛异常
    expect(await backend.exists('/notes/'), isTrue);
  });

  test('upload + download round-trip', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final etag = await backend.upload('/notes/a.json', bytes);
    expect(etag, isNotEmpty);

    final downloaded = await backend.download('/notes/a.json');
    expect(downloaded, bytes);
  });

  test('upload with ifMatchEtag mismatch throws ETagMismatchException',
      () async {
    final bytes = Uint8List.fromList([1]);
    final etag = await backend.upload('/notes/a.json', bytes);
    // 同 path 用错误的 etag 上传
    expect(
      () => backend.upload('/notes/a.json', bytes, ifMatchEtag: 'wrong'),
      throwsA(isA<ETagMismatchException>()),
    );
    // 正确 etag 不抛
    await backend.upload('/notes/a.json', bytes, ifMatchEtag: etag);
  });

  test('listDir returns files under path', () async {
    final bytes1 = Uint8List.fromList([1]);
    final bytes2 = Uint8List.fromList([2, 2]);
    final etag1 = await backend.upload('/notes/a.json', bytes1);
    final etag2 = await backend.upload('/notes/b.json', bytes2);
    final files = await backend.listDir('/notes/');
    expect(files.map((f) => f.path).toSet(), {'/notes/a.json', '/notes/b.json'});

    final aFile = files.firstWhere((f) => f.path == '/notes/a.json');
    expect(aFile.size, 1);
    expect(aFile.etag, etag1);

    final bFile = files.firstWhere((f) => f.path == '/notes/b.json');
    expect(bFile.size, 2);
    expect(bFile.etag, etag2);
  });

  test('delete removes file; exists returns false', () async {
    await backend.upload('/notes/a.json', Uint8List.fromList([1]));
    await backend.delete('/notes/a.json');
    expect(await backend.exists('/notes/a.json'), isFalse);
  });

  test('upload with ifMatchEtag on non-existing path succeeds (first push)',
      () async {
    // 文件不存在时，即使带 ifMatchEtag 也不抛——允许首次推送
    final bytes = Uint8List.fromList([1]);
    final etag = await backend.upload(
      '/notes/new.json',
      bytes,
      ifMatchEtag: '"any"',
    );
    expect(etag, isNotEmpty);
    expect(await backend.exists('/notes/new.json'), isTrue);
  });

  test('download non-existing file throws RemoteFileNotFoundException',
      () async {
    expect(
      () => backend.download('/notes/missing.json'),
      throwsA(isA<RemoteFileNotFoundException>()),
    );
  });

  test('delete non-existing file is no-op', () async {
    // 不抛异常
    await backend.delete('/notes/never-existed.json');
    // 其他文件不受影响
    await backend.upload('/notes/a.json', Uint8List.fromList([1]));
    await backend.delete('/notes/never-existed.json');
    expect(await backend.exists('/notes/a.json'), isTrue);
  });

  test('listDir on empty directory returns empty list', () async {
    await backend.mkcol('/empty/');
    final files = await backend.listDir('/empty/');
    expect(files, isEmpty);
  });

  test('listDir does not recurse into subdirectories', () async {
    await backend.upload('/notes/a.json', Uint8List.fromList([1]));
    await backend.upload('/notes/sub/b.json', Uint8List.fromList([2]));
    final files = await backend.listDir('/notes/');
    // 只列出 /notes/a.json，不含 /notes/sub/b.json
    expect(files.map((f) => f.path).toList(), ['/notes/a.json']);
  });
}
