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

  /// 测试连接：PROPFIND 根目录，验证地址+凭据+WebDAV 能力。
  ///
  /// 比 [exists] 用 HEAD 更彻底：PROPFIND 是 WebDAV 核心动词，
  /// 能暴露 401（认证）/403（权限）/404（路径）/501（非 WebDAV 服务）。
  /// 失败时抛带中文诊断的 [Exception]，UI 可直接显示。
  @override
  Future<void> testConnection(String rootPath) async {
    try {
      await client.propfind(rootPath);
    } on DioException catch (e) {
      // 404 在测试连接时也算失败（路径不存在），不走"文件不存在"语义
      _raiseDiagnosed(e);
    }
  }

  @override
  Future<void> mkcol(String path) async {
    try {
      await client.mkcol(path);
    } on DioException catch (e) {
      // 405 Method Not Allowed：目录已存在，视为成功
      if (e.response?.statusCode != 405) _raiseDiagnosed(e);
    }
  }

  /// 把 [DioException] 翻译成用户可读的中文诊断。
  ///
  /// WebDAV 测试连接时最常见的几种失败：
  /// - 403：坚果云用错密码（必须用应用密码）、或 URL 路径错、或流量超限
  /// - 401：Basic/Digest 认证失败（用户名/密码错）
  /// - 404：URL 路径不存在（共享名拼错）
  /// - 超时/连接拒绝：网络或服务器地址错
  ///
  /// 抛出 [Exception] 携带中文 message，UI 可直接显示。
  Never _raiseDiagnosed(DioException e) {
    final code = e.response?.statusCode;
    final server = e.response?.headers.value('server') ?? '';
    final isJianguoyun = client.baseUrl.contains('jianguoyun.com') ||
        server.toLowerCase().contains('jianguoyun');

    String diag;
    switch (code) {
      case 401:
        diag = '认证失败（401）：用户名或应用密码错误。'
            '坚果云必须用「账户信息 → 安全选项 → 添加应用」生成的应用密码，不是登录密码。';
        break;
      case 403:
        if (isJianguoyun) {
          diag = '坚果云拒绝访问（403）：最常见原因是用了登录密码而非应用密码，'
              '或当月流量超限（免费版 1GB 上传 / 3GB 下载）。'
              '请到 jianguoyun.com 账户安全选项生成新应用密码后再试。';
        } else {
          diag = '服务器拒绝访问（403）：账号无权限，或 URL 路径不允许访问。';
        }
        break;
      case 404:
        diag = '路径不存在（404）：WebDAV URL 或根目录拼写错误。'
            '请确认 URL 含共享路径（如 https://dav.jianguoyun.com/dav/）。';
        break;
      case 500:
      case 502:
      case 503:
        diag = '服务器错误（$code）：WebDAV 服务端异常，稍后重试。';
        break;
      default:
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.sendTimeout:
          case DioExceptionType.receiveTimeout:
            diag = '连接超时：WebDAV 服务器地址不通或响应过慢，请检查 URL 和网络。';
            break;
          case DioExceptionType.connectionError:
            diag = '无法连接服务器：地址错误或网络不可达。'
                '错误详情：${e.error}';
            break;
          case DioExceptionType.badCertificate:
            diag = 'SSL 证书校验失败：自签名证书需在客户端信任，或不安全的 HTTPS。';
            break;
          default:
            diag = 'WebDAV 请求失败（状态码 $code，类型 ${e.type}）。'
                '错误详情：${e.error}';
        }
    }
    throw Exception(diag);
  }

  @override
  Future<bool> exists(String path) async {
    try {
      await client.head(path);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false;
      _raiseDiagnosed(e);
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
      _raiseDiagnosed(e);
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
      _raiseDiagnosed(e);
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await client.delete(path);
    } on DioException catch (e) {
      // 404 视为已删除，成功
      if (e.response?.statusCode == 404) return;
      _raiseDiagnosed(e);
    }
  }

  @override
  Future<List<RemoteFile>> listDir(String path) async {
    Response<String> resp;
    try {
      resp = await client.propfind(path);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const [];
      _raiseDiagnosed(e);
    }
    final result = parseMultiStatus(resp.data ?? '', basePath: path);

    // 坚果云 WebDAV 限制：单次 PROPFIND 最多返回约 750 项。
    // 超过会静默截断，导致上层 _pullPhase 反向删除逻辑误判本地笔记
    // 为"远端已删除"而软删——属于静默数据丢失，必须主动检测拦截。
    // 阈值 749（解析后已剔除目录自身），命中即抛错让用户感知。
    // 参考：https://help.jianguoyun.com/?p=2064
    final isJianguoyun = client.baseUrl.contains('jianguoyun.com');
    if (isJianguoyun && result.length >= 749) {
      throw Exception(
        '坚果云单目录文件数已达上限（约 750），列表被截断。'
        '为防止误删本地笔记，同步已中止。'
        '请到坚果云网页端清理冲突副本或迁移到子目录后重试。',
      );
    }
    return result;
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
  /// 跳过目录自引用：判定方式三选一，命中任一即跳过——
  ///   1. href 以 `/` 结尾（标准目录 href）
  ///   2. propstat 含 `<resourcetype><collection/></resourcetype>`（WebDAV 规范的目录标记）
  ///   3. 规范化后路径等于 [basePath]（覆盖坚果云等返回无尾斜杠 host 绝对 href 的情况）
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

    // basePath 规范化为"path 段"，用于跨协议/host 比较
    final normalizedBase = _normalizePath(_stripToPath(basePath));

    for (final response in allResponses) {
      final href = _findText(response, 'href');
      if (href == null) continue;

      // 跳过目录自身：方式 1（href 以 / 结尾）
      if (href.endsWith('/')) continue;
      // 跳过目录自身：方式 2（resourcetype 含 collection）
      if (_isCollection(response)) continue;
      // 跳过目录自身：方式 3（path 段后缀匹配，兼容坚果云 host 绝对 href）
      // 坚果云返回 /dav/notes-app/notes（含 /dav/ 共享名前缀、无尾斜杠、
      // 不带 <resourcetype>），方式 1/2 都失效，靠段后缀匹配兜底。
      if (_isSameResource(href, normalizedBase)) continue;

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

  /// 判断 response 是否含 `<resourcetype><collection/></resourcetype>`。
  /// 这是 WebDAV 规范中标记目录的标准方式，比 href 尾斜杠更可靠。
  bool _isCollection(XmlElement response) {
    if (response.findAllElements('collection', namespace: 'DAV:').isNotEmpty) {
      return true;
    }
    // 退化：不限定命名空间
    return response.findAllElements('collection').isNotEmpty;
  }

  /// 从可能的完整 URL 或 host 绝对路径中剥离出纯 path 段。
  ///
  /// 例：
  ///   https://dav.jianguoyun.com/dav/notes-app/notes  →  /dav/notes-app/notes
  ///   /dav/notes-app/notes/                            →  /dav/notes-app/notes
  ///   /dav/notes-app/notes                             →  /dav/notes-app/notes
  /// 用于跨协议/host 比较 href 与 basePath。
  String _stripToPath(String urlOrPath) {
    if (urlOrPath.contains('://')) {
      try {
        return Uri.parse(urlOrPath).path;
      } catch (_) {
        // 解析失败，粗暴切掉协议头
        final idx = urlOrPath.indexOf('/', urlOrPath.indexOf('://') + 3);
        return idx >= 0 ? urlOrPath.substring(idx) : urlOrPath;
      }
    }
    return urlOrPath;
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

  /// 判断 [href]（可能含 /dav/ 等共享名前缀、host 绝对路径、完整 URL）
  /// 与 [normalizedBase]（已规范化的 path 段）是否指向同一资源。
  ///
  /// 采用段后缀匹配而非完全相等：坚果云返回
  ///   href       = /dav/notes-app/notes
  ///   normalizedBase = /notes-app/notes
  /// href 以 `/normalizedBase` 结尾且前一字符是 `/`（段边界）即判定相等。
  /// 完全相等仍优先（避免短 base 误匹配，如 base=/notes 匹配到 /x/notes）。
  bool _isSameResource(String href, String normalizedBase) {
    final normalizedHref = _normalizePath(_stripToPath(href));
    if (normalizedHref == normalizedBase) return true;
    return normalizedHref.endsWith('/$normalizedBase') &&
        normalizedHref.length > normalizedBase.length;
  }
}
