import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// HTTP Digest 认证拦截器（RFC 2617 / RFC 7616 qop=auth）。
///
/// 工作流程：
/// 1. 主请求带上 Basic 头（[setCredentials] 设置的）
/// 2. 服务器若要 Digest，回 401 + `WWW-Authenticate: Digest ...`
/// 3. 本拦截器解析 challenge，计算 response，用 `Authorization: Digest ...` 重试一次
///
/// 仅缓存单次 nonce；如果服务器 nonce 过期会再次 401，由调用方决策。
///
/// 使用场景：很多家用 NAS（绿联/某些群晖配置/嵌入式设备）只支持 Digest；
/// dio 默认不带 Digest，所以需要本拦截器兜底。
class DigestAuthInterceptor extends Interceptor {
  final Dio _dio;

  DigestAuthInterceptor(this._dio);

  String? username;
  String? password;

  /// 服务端 challenge 解析结果（每次 401 刷新）
  String? _realm;
  String? _nonce;
  String? _qop;
  String? _opaque;
  String _algorithm = 'MD5';

  int _nc = 0;

  void setCredentials(String user, String pwd) {
    username = user;
    password = pwd;
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    if (response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    final authHeader = response!.headers.value('www-authenticate');
    if (authHeader == null) {
      handler.next(_enhanceError(err, null));
      return;
    }

    // Basic 服务器 + 我们已发 Basic 仍 401 = 密码错。直接报错带 WWW-Authenticate。
    final lower = authHeader.toLowerCase();
    if (lower.startsWith('basic')) {
      handler.next(_enhanceError(err, authHeader));
      return;
    }

    // Digest 服务器：解析 challenge，重试一次
    if (!lower.startsWith('digest')) {
      handler.next(_enhanceError(err, authHeader));
      return;
    }
    if (username == null || password == null) {
      handler.next(_enhanceError(err, authHeader));
      return;
    }

    if (!_parseChallenge(authHeader)) {
      handler.next(_enhanceError(err, authHeader));
      return;
    }

    final options = err.requestOptions;
    _nc += 1;
    final authValue = _buildDigestHeader(
      method: options.method.toUpperCase(),
      uri: _relativeUri(options.path),
    );
    options.headers['Authorization'] = authValue;

    try {
      final retryResponse = await _dio.fetch(options);
      handler.resolve(retryResponse);
    } on DioException catch (e) {
      handler.next(_enhanceError(e, authHeader));
    }
  }

  /// 把完整 URL 转换为 Digest 计算需要的 request-uri（path + query）。
  ///
  /// RFC 2617 要求 uri 字段为 request-uri，多数实现用相对路径。
  String _relativeUri(String fullPath) {
    final uri = Uri.tryParse(fullPath);
    if (uri == null) return fullPath;
    if (uri.host.isEmpty) return fullPath; // 已经是相对路径
    final pathAndQuery = uri.path + (uri.query.isEmpty ? '' : '?${uri.query}');
    return pathAndQuery.isEmpty ? '/' : pathAndQuery;
  }

  /// 把 WWW-Authenticate 头塞到错误信息里，方便用户在 UI 看清认证方式。
  DioException _enhanceError(DioException err, String? authHeader) {
    final code = err.response?.statusCode;
    final buf = StringBuffer('HTTP $code Unauthorized');
    if (authHeader != null) {
      buf.write(' · WWW-Authenticate: $authHeader');
    }
    buf.write(
        '\n常见原因：账号或应用密码错误；或服务器要求 Digest/其他认证方式而当前只发了 Basic。');
    return DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: buf.toString(),
      message: err.message,
    );
  }

  /// 解析 `Digest realm="...", nonce="...", qop="auth", opaque="..."` 形如的 challenge。
  bool _parseChallenge(String header) {
    // 去掉 "Digest " 前缀
    final rest = header.substring(header.indexOf(' ') + 1);
    _realm = _extract(rest, 'realm');
    _nonce = _extract(rest, 'nonce');
    _qop = _extract(rest, 'qop');
    _opaque = _extract(rest, 'opaque');
    final alg = _extract(rest, 'algorithm');
    if (alg != null) _algorithm = alg.toUpperCase();
    if (_realm == null || _nonce == null) return false;
    if (_qop != null && !_qop!.contains('auth')) return false;
    return true;
  }

  /// 提取形如 `key="value"` 或 `key=value` 的值（逗号分隔）。
  String? _extract(String src, String key) {
    final pattern =
        RegExp('$key=(?:"([^"]+)"|([^,\\s]+))', caseSensitive: false);
    final m = pattern.firstMatch(src);
    if (m == null) return null;
    return m.group(1) ?? m.group(2);
  }

  String _buildDigestHeader({required String method, required String uri}) {
    final cnonce = _generateNonce();
    final ncStr = _nc.toRadixString(16).padLeft(8, '0');

    final ha1Input = '$username:$_realm:$password';
    final ha1 = md5.convert(utf8.encode(ha1Input)).toString();

    final ha2Input = '$method:$uri';
    final ha2 = md5.convert(utf8.encode(ha2Input)).toString();

    final String responseInput;
    if (_qop != null && _qop!.contains('auth')) {
      responseInput = '$ha1:$_nonce:$ncStr:$cnonce:auth:$ha2';
    } else {
      responseInput = '$ha1:$_nonce:$ha2';
    }
    final responseHash = md5.convert(utf8.encode(responseInput)).toString();

    final parts = <String>[
      'username="$username"',
      'realm="$_realm"',
      'nonce="$_nonce"',
      'uri="$uri"',
      'algorithm=$_algorithm',
      'response="$responseHash"',
    ];
    if (_qop != null && _qop!.contains('auth')) {
      parts.addAll([
        'qop=auth',
        'nc=$ncStr',
        'cnonce="$cnonce"',
      ]);
    }
    if (_opaque != null) {
      parts.add('opaque="$_opaque"');
    }
    return 'Digest ${parts.join(', ')}';
  }

  String _generateNonce() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
