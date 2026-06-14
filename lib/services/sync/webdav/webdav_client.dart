import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'digest_auth_interceptor.dart';

/// 底层 WebDAV HTTP 调用封装。
///
/// 与 [WebDAVBackend] 解耦：只负责发请求、解析响应，不涉及业务逻辑。
/// 业务层（WebDAVBackend）负责状态码转换、错误语义化。
class WebDAVClient {
  final Dio dio;

  /// 可变：用户在设置页修改 URL 后由 [WebDAVBackend.reconfigure] 更新。
  /// 启动时可能为空（首次配置前），发请求会因 URI 无 host 失败。
  String baseUrl;

  /// 当前凭据（每次 onRequest 注入到 Authorization 头，不依赖 dio.options.headers
  /// 在没有 baseUrl 时的潜在合并问题）。
  String? _username;
  String? _password;

  /// Digest 认证兜底拦截器：服务器要求 Digest 时自动重试。
  final DigestAuthInterceptor _digestInterceptor;

  WebDAVClient({Dio? dio, required this.baseUrl})
      : dio = dio ?? Dio(),
        _digestInterceptor = DigestAuthInterceptor(dio ?? Dio()) {
    // Basic 认证注入：每次请求都用最新凭据计算 header，
    // 避免 dio.options.headers 在某些路径下不合并的问题。
    this.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_username != null && _password != null) {
          final creds = base64Encode(utf8.encode('$_username:$_password'));
          options.headers['Authorization'] = 'Basic $creds';
        }
        handler.next(options);
      },
    ));
    this.dio.interceptors.add(_digestInterceptor);
  }

  /// 设置凭据：同时写 Basic 头（坚果云等）和给 Digest 拦截器留底（家用 NAS 等）。
  void setBasicAuth(String username, String password) {
    _username = username;
    _password = password;
    _digestInterceptor.setCredentials(username, password);
  }

  /// MKCOL：创建目录。已存在时服务器返回 405，由业务层判定为成功。
  Future<Response> mkcol(String path) async {
    return dio.request(
      fullUrl(path),
      options: Options(method: 'MKCOL'),
    );
  }

  /// PUT：上传文件。可选 [ifMatchEtag] 用于乐观锁（HTTP If-Match）。
  Future<Response> put(
    String path,
    Uint8List bytes, {
    String? ifMatchEtag,
  }) async {
    return dio.put(
      fullUrl(path),
      data: bytes,
      options: Options(
        headers: {
          'Content-Length': bytes.length,
          // Uint8List 必须显式指定 Content-Type，否则 dio 的
          // ImplyContentTypeInterceptor 会打印警告（请求仍能成功，但污染日志）。
          'Content-Type': 'application/octet-stream',
          if (ifMatchEtag != null) 'If-Match': ifMatchEtag, // ignore: use_null_aware_elements
        },
      ),
    );
  }

  /// GET：下载文件原始字节。
  Future<Response<Uint8List>> get(String path) async {
    return dio.get<Uint8List>(
      fullUrl(path),
      options: Options(responseType: ResponseType.bytes),
    );
  }

  /// DELETE：删除文件。不存在时服务器返回 404，由业务层判定为成功。
  Future<Response> delete(String path) async {
    return dio.delete(fullUrl(path));
  }

  /// HEAD：检查存在性。
  Future<Response> head(String path) async {
    return dio.head(fullUrl(path));
  }

  /// PROPFIND：列出目录元数据。返回 multistatus XML 字符串。
  Future<Response<String>> propfind(String path) async {
    return dio.request<String>(
      fullUrl(path),
      data: '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:getetag/>
  </d:prop>
</d:propfind>''',
      options: Options(
        method: 'PROPFIND',
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  /// 拼接完整 URL：处理 baseUrl 末尾 `/` 和 path 开头 `/` 的边界。
  ///
  /// path 有两种来源：
  /// 1. 调用方拼的相对路径（如 `rootPath + 'notes/xxx.json'`）：以 `/` 开头，
  ///    但不含 baseUrl 的 path 部分。
  /// 2. PROPFIND 返回的 href：服务器给的 host 绝对路径，**已含** baseUrl 的
  ///    path 部分（如 baseUrl=`https://x/dav/` 时 href=`/dav/notes/a.json`）。
  ///
  /// 第 2 种情况如果直接 `baseUrl + path` 会重复 path 段（如 `/dav/dav/notes/...`）
  /// 导致 404。所以需要识别并去重。
  ///
  /// 防御：path 是完整 URL（http/https 开头）时直接返回。
  String fullUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;

    // 检查 path 是否已包含 baseUrl 的 path 部分（host 绝对路径）。
    // 例如 baseUrl=`https://x/dav/` → basePath=`/dav/` → baseRelative=`dav/`，
    // 若 normalizedPath 以 `dav/` 开头说明是 PROPFIND href，重复了，需去重。
    final baseUri = Uri.parse(baseUrl);
    final basePath = baseUri.path; // 如 `/dav/`、`/nvme12-xxx/`、`/` 或空
    if (basePath.length > 1) {
      final baseRelative =
          basePath.startsWith('/') ? basePath.substring(1) : basePath;
      if (baseRelative.isNotEmpty && normalizedPath.startsWith(baseRelative)) {
        // 已含 baseUrl path：替换 baseUri 的 path，保留 scheme/host/port
        return baseUri.replace(path: '/$normalizedPath').toString();
      }
    }

    // 相对路径：直接拼 baseUrl + path
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return '$base$normalizedPath';
  }
}
