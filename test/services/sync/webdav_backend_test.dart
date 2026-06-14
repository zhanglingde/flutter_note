import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note/services/sync/sync_backend.dart';
import 'package:note/services/sync/webdav/webdav_backend.dart';
import 'package:note/services/sync/webdav/webdav_client.dart';

const _samplePropfindResponse = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/notes/a.json</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>100</d:getcontentlength>
        <d:getlastmodified>Mon, 14 Jun 2026 10:00:00 GMT</d:getlastmodified>
        <d:getetag>"etag-a"</d:getetag>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/notes/b.json</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>200</d:getcontentlength>
        <d:getlastmodified>Tue, 15 Jun 2026 10:00:00 GMT</d:getlastmodified>
        <d:getetag>"etag-b"</d:getetag>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

void main() {
  late WebDAVBackend backend;

  setUp(() {
    backend = WebDAVBackend(baseUrl: 'https://dav.example.com/dav/');
  });

  test('authenticate stores credentials and sets basic auth header', () async {
    await backend.authenticate(
      const Credentials(username: 'u', password: 'p'),
    );
    // 没有异常即可——header 设置是 client 内部状态
  });

  test('parseMultiStatus extracts files from PROPFIND response', () {
    final files = backend.parseMultiStatusForTesting(
      _samplePropfindResponse,
      basePath: '/dav/notes/',
    );
    expect(files.length, 2);
    expect(files[0].path, '/dav/notes/a.json');
    expect(files[0].size, 100);
    expect(files[0].etag, '"etag-a"');
    expect(files[1].path, '/dav/notes/b.json');
    expect(files[1].etag, '"etag-b"');
  });

  test('parseMultiStatus skips directory self-entry', () {
    final xml = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/notes/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/notes/a.json</d:href>
    <d:propstat>
      <d:prop>
        <d:getetag>"etag-a"</d:getetag>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';
    final files = backend.parseMultiStatusForTesting(
      xml,
      basePath: '/dav/notes/',
    );
    expect(files.length, 1);
    expect(files.first.path, '/dav/notes/a.json');
  });

  test('parseMultiStatus returns empty for empty body', () {
    final files = backend.parseMultiStatusForTesting('', basePath: '/x/');
    expect(files, isEmpty);
  });

  test('parseMultiStatus handles missing etag gracefully', () {
    final xml = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/notes/no-etag.json</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>50</d:getcontentlength>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';
    final files = backend.parseMultiStatusForTesting(
      xml,
      basePath: '/dav/notes/',
    );
    expect(files.length, 1);
    expect(files.first.etag, isNull);
    expect(files.first.size, 50);
  });

  // ============================================================
  // 运行时重配置：main 启动时 baseUrl 必然为空（首次配置前），用户在设置页填 URL 后
  // 必须能更新到 client，否则后续请求因 URI 无 host 失败。
  // ============================================================
  test('reconfigure updates baseUrl and credentials at runtime', () {
    final client = WebDAVClient(dio: Dio(), baseUrl: '');
    final backend = WebDAVBackend.withClient(client);

    // 启动时 baseUrl=''：模拟 main.dart 启动场景
    expect(client.fullUrl('/notes-app/notes/'), '/notes-app/notes/',
        reason: '空 baseUrl 下 fullUrl 是相对路径');

    // 用户在设置页保存了新配置
    backend.reconfigure(
      baseUrl: 'https://dav.jianguoyun.com/dav/',
      credentials: const Credentials(username: 'u', password: 'p'),
    );

    expect(
      client.fullUrl('/notes-app/notes/'),
      'https://dav.jianguoyun.com/dav/notes-app/notes/',
      reason: 'reconfigure 后 baseUrl 必须立刻生效',
    );
  });

  // ============================================================
  // 极空间/坚果云等 NAS 场景：baseUrl 含 path 部分（如 /dav/ 或 /nvme12-xxx/），
  // 服务器 PROPFIND 返回的 href 是 host 绝对路径，已含这个 path 前缀。
  // fullUrl 必须识别这种情况，避免 baseUrl path 被重复拼接。
  // 之前的 bug：path=/dav/notes/a.json + baseUrl=https://x/dav/ 拼成 https://x/dav/dav/notes/a.json → 404
  // ============================================================
  test(
      'fullUrl does not duplicate baseUrl path when path is host-absolute (PROPFIND href)',
      () {
    final client = WebDAVClient(
      dio: Dio(),
      baseUrl: 'https://dav.jianguoyun.com/dav/',
    );

    // PROPFIND 返回的 href：含 /dav/ 前缀
    expect(
      client.fullUrl('/dav/notes/abc.json'),
      'https://dav.jianguoyun.com/dav/notes/abc.json',
      reason: 'href 已含 /dav/ 前缀，必须只拼一次',
    );
  });

  test('fullUrl handles NAS baseUrl with shared-folder path prefix', () {
    // 极空间场景：baseUrl 含共享名（/nvme12-xxx/）
    final client = WebDAVClient(
      dio: Dio(),
      baseUrl: 'http://192.168.3.60:5005/nvme12-18779354943a/',
    );

    // 用户配置的相对 rootPath
    expect(
      client.fullUrl('/notes-app/'),
      'http://192.168.3.60:5005/nvme12-18779354943a/notes-app/',
      reason: '相对 path 正常拼接 baseUrl',
    );

    // PROPFIND 返回的 host 绝对 href（含共享名前缀）
    expect(
      client.fullUrl('/nvme12-18779354943a/notes-app/notes/1780404559641.json'),
      'http://192.168.3.60:5005/nvme12-18779354943a/notes-app/notes/1780404559641.json',
      reason: 'PROPFIND href 含共享名前缀，不能重复拼接',
    );
  });

  test('fullUrl still works when baseUrl has no path part', () {
    final client = WebDAVClient(
      dio: Dio(),
      baseUrl: 'http://192.168.3.60:5005',
    );

    expect(
      client.fullUrl('/notes-app/notes/a.json'),
      'http://192.168.3.60:5005/notes-app/notes/a.json',
    );
  });
}
