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

  /// 伪装成原生 Cyberduck 客户端的全套请求头（最大化模拟）。
  ///
  /// 部分服务器会按 UA + 请求头组合白名单放行客户端：
  /// - 坚果云：不校验，任意 UA 都行
  /// - 中国科技云数据胶囊（data.cstcloud.cn）：只放行官方认可客户端
  ///   （Cyberduck / rclone / RaiDrive / Win 网络映射 等），
  ///   Dio 默认 UA（Dart/3.x）会被判为非法程序，直接 403 Client type mismatch；
  ///   仅改 UA 仍可能被「请求头组合不完整」识别出来，故补齐 Cyberduck 原生发的全套头。
  ///
  /// 写到实例默认头而非每请求 Options，确保 MKCOL/PUT/GET/DELETE/HEAD/PROPFIND
  /// 全覆盖；per-request 仍可覆盖（如 PROPFIND 的 Depth、PUT 的 Content-Type）。
  static const String _userAgent =
      'Cyberduck/9.0.1 (Windows 10/10.0) (x86_64)';

  static const Map<String, String> _cyberduckHeaders = {
    'user-agent': _userAgent,
    'Accept': '*/*',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive',
  };

  WebDAVClient({Dio? dio, required this.baseUrl})
      : dio = dio ?? Dio(),
        _digestInterceptor = DigestAuthInterceptor(dio ?? Dio()) {
    // 模拟 Cyberduck 的全套默认请求头：规避按客户端类型 / 请求头组合拦截的服务器。
    // 写到实例默认头，MKCOL/PUT/GET/DELETE/HEAD/PROPFIND 全覆盖。
    this.dio.options.headers.addAll(_cyberduckHeaders);
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
    // 诊断日志拦截器：所有请求/响应（含错误响应）都打到 debugPrint，
    // 用于排查 WebDAV 连接问题（403/401/超时/URL 错等）。
    // 放在最后，确保能拿到 Digest 重试后的最终响应。
    this.dio.interceptors.add(_DebugLogInterceptor());
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

/// WebDAV 诊断日志拦截器（仅 [kDebugMode] 下生效，release 完全静默）。
///
/// 把每次请求/响应的关键信息打印到 debugPrint，便于在控制台定位
/// 401/403/404/超时 等连接问题，并观察 PROPFIND/PUT 的实际收发内容：
/// - 请求（onRequest）：方法、完整 URL、脱敏后的头、body 大小/预览
/// - 响应（onResponse）：状态码、Content-Length、body 预览
///   （XML/JSON 文本截断预览，二进制只打印长度，避免刷屏/泄露笔记内容）
/// - 错误（onError）：DioException 类型、状态码、响应头、响应体
///
/// 敏感头（Authorization、Cookie）会被脱敏为 `***`，不会泄露凭据。
/// release 模式直接 return，不做任何字符串拼接，零开销。
class _DebugLogInterceptor extends Interceptor {
  /// 文本 body 预览最大字符数（避免 PROPFIND 大 XML 刷屏）
  static const int _maxTextPreview = 1000;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!kDebugMode) {
      handler.next(options);
      return;
    }
    final buf = StringBuffer('[WebDAV] → ${options.method} ${options.uri}');
    final safeHeaders = _sanitizeHeaders(options.headers);
    if (safeHeaders.isNotEmpty) buf.write('\n  headers: $safeHeaders');
    final bodyDesc = _describeBody(options.data);
    if (bodyDesc != null) buf.write('\n  body: $bodyDesc');
    debugPrint(buf.toString());
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!kDebugMode) {
      handler.next(response);
      return;
    }
    final req = response.requestOptions;
    final buf = StringBuffer(
        '[WebDAV] ← ${req.method} ${req.uri} ${response.statusCode}');
    final len = response.headers.value('content-length');
    if (len != null) buf.write(' ($len bytes)');
    final bodyDesc = _describeBody(response.data);
    if (bodyDesc != null) buf.write('\n  body: $bodyDesc');
    debugPrint(buf.toString());
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!kDebugMode) {
      handler.next(err);
      return;
    }
    final req = err.requestOptions;
    final code = err.response?.statusCode;
    debugPrint(
        '[WebDAV] ✗ ${req.method} ${req.uri} 失败 type=${err.type} status=$code');
    if (err.response != null) {
      debugPrint('[WebDAV] 错误响应头 '
          'Server=${err.response?.headers.value('server')} '
          'WWW-Authenticate=${err.response?.headers.value('www-authenticate')}');
      final bodyDesc = _describeBody(err.response?.data);
      if (bodyDesc != null) debugPrint('[WebDAV] 错误响应体: $bodyDesc');
    }
    handler.next(err);
  }

  /// 脱敏请求头：Authorization / Cookie 替换为 `***`，避免凭据进入日志
  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final result = Map<String, dynamic>.from(headers);
    for (final key in result.keys.toList()) {
      final lower = key.toLowerCase();
      if (lower == 'authorization' || lower == 'cookie') {
        result[key] = '***';
      }
    }
    return result;
  }

  /// 描述 body：
  /// - 二进制（Uint8List / List）→ 只打印字节数，避免刷屏和泄露笔记内容
  /// - 字符串（PROPFIND 的 XML、错误响应 HTML）→ 截断到 [_maxTextPreview] 预览
  /// - null / 空 → 返回 null（调用方据此跳过整行打印）
  String? _describeBody(dynamic data) {
    if (data == null) return null;
    if (data is Uint8List) {
      return data.isEmpty ? null : '<bytes ${data.length}B>';
    }
    if (data is List<int>) {
      return data.isEmpty ? null : '<bytes ${data.length}B>';
    }
    if (data is String) {
      if (data.isEmpty) return null;
      return data.length > _maxTextPreview
          ? '${data.substring(0, _maxTextPreview)}…(${data.length} chars)'
          : data;
    }
    return data.toString();
  }
}
