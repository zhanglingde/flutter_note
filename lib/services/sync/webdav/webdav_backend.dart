import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../sync_backend.dart';
import 'webdav_client.dart';

/// 坚果云等 WebDAV 服务的 [SyncBackend] 实现。
///
/// 业务层：负责状态码到 [SyncBackend] 语义的转换。
/// HTTP 层细节封装在 [WebDAVClient] 中。
class WebDAVBackend implements SyncBackend {
  final WebDAVClient client;

  /// 生产构造函数：用 [baseUrl] 创建默认 [Dio]。
  /// 如需自定义超时、interceptor，注入 [dio]。
  WebDAVBackend({
    required String baseUrl,
    Dio? dio,
  }) : client = WebDAVClient(dio: dio ?? Dio(), baseUrl: baseUrl);

  /// 测试用：直接注入 [WebDAVClient]。
  @visibleForTesting
  WebDAVBackend.withClient(this.client);

  @override
  Future<void> authenticate(Credentials creds) async {
    client.setBasicAuth(creds.username, creds.password);
  }

  /// 运行时更新 baseUrl 和认证信息。
  ///
  /// 调用时机：用户在 SyncSettingsScreen 保存配置后立即调用，
  /// 让运行中的 SyncService 实例感知新配置——避免重启应用。
  void reconfigure({required String baseUrl, required Credentials credentials}) {
    client.baseUrl = baseUrl;
    client.setBasicAuth(credentials.username, credentials.password);
  }

  @override
  Future<void> mkcol(String path) async {
    try {
      await client.mkcol(path);
    } on DioException catch (e) {
      // 405 Method Not Allowed：目录已存在，视为成功
      if (e.response?.statusCode != 405) rethrow;
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      await client.head(path);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false;
      rethrow;
    }
  }

  @override
  Future<String> upload(
    String path,
    Uint8List bytes, {
    String? ifMatchEtag,
  }) async {
    try {
      final resp = await client.put(path, bytes, ifMatchEtag: ifMatchEtag);
      final etag = resp.headers.value('etag');
      if (etag == null || etag.isEmpty) {
        // 服务器没返回 etag，用一个退化值
        return '"unknown-${DateTime.now().millisecondsSinceEpoch}"';
      }
      return etag;
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw ETagMismatchException(
          path: path,
          expected: ifMatchEtag,
          actual: e.response?.headers.value('etag'),
        );
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List> download(String path) async {
    try {
      final resp = await client.get(path);
      if (resp.data == null) return Uint8List(0);
      return resp.data!;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw RemoteFileNotFoundException(path);
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await client.delete(path);
    } on DioException catch (e) {
      // 404 视为已删除，成功
      if (e.response?.statusCode != 404) rethrow;
    }
  }

  @override
  Future<List<RemoteFile>> listDir(String path) async {
    final resp = await client.propfind(path);
    return parseMultiStatus(resp.data ?? '', basePath: path);
  }

  /// 解析 PROPFIND 多状态响应（[visibleForTesting] 暴露给测试）。
  ///
  /// 直接单元测试，避免依赖 HTTP mock 对 PROPFIND 的不稳定支持。
  @visibleForTesting
  List<RemoteFile> parseMultiStatusForTesting(
    String body, {
    required String basePath,
  }) {
    return parseMultiStatus(body, basePath: basePath);
  }

  /// 解析 PROPFIND multistatus XML 响应，提取文件列表。
  ///
  /// 兼容 DAV: 命名空间和默认命名空间两种写法（部分服务器实现不一致）。
  /// 跳过目录自引用（href 以 `/` 结尾或等于 [basePath]）。
  /// 日期解析失败时降级为 epoch，避免单条记录异常导致整体失败。
  List<RemoteFile> parseMultiStatus(String body, {required String basePath}) {
    if (body.isEmpty) return [];
    final document = XmlDocument.parse(body);

    final result = <RemoteFile>[];
    final responses = document
        .findAllElements('response', namespace: 'DAV:')
        .toList();
    // 部分服务器用默认命名空间，退化为不限定
    final allResponses =
        responses.isNotEmpty ? responses : document.findAllElements('response').toList();

    for (final response in allResponses) {
      final href = _findText(response, 'href');
      if (href == null) continue;

      // 跳过目录自身（href 以 / 结尾，或规范化后等于 basePath）
      if (href.endsWith('/')) continue;
      if (_normalizePath(href) == _normalizePath(basePath)) continue;

      final sizeStr = _findText(response, 'getcontentlength');
      final lmStr = _findText(response, 'getlastmodified');
      final etag = _findText(response, 'getetag');

      DateTime lastModified;
      try {
        lastModified = lmStr != null
            ? HttpDate.parse(lmStr)
            : DateTime.fromMillisecondsSinceEpoch(0);
      } catch (_) {
        lastModified = DateTime.fromMillisecondsSinceEpoch(0);
      }

      result.add(RemoteFile(
        path: href,
        size: int.tryParse(sizeStr ?? '') ?? 0,
        lastModified: lastModified,
        etag: etag,
      ));
    }
    return result;
  }

  /// 在 DAV: 命名空间下查找元素文本；找不到则退化为不限定命名空间。
  String? _findText(XmlElement element, String name) {
    final davElements = element.findAllElements(name, namespace: 'DAV:');
    if (davElements.isNotEmpty) return davElements.first.innerText;
    final anyElements = element.findAllElements(name);
    if (anyElements.isNotEmpty) return anyElements.first.innerText;
    return null;
  }

  /// 路径规范化：补齐前导 `/`，去掉末尾 `/`。
  String _normalizePath(String p) {
    if (!p.startsWith('/')) p = '/$p';
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }
}
