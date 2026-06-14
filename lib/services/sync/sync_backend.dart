import 'dart:typed_data';

/// 后端凭据
class Credentials {
  final String username;
  final String password;

  const Credentials({required this.username, required this.password});
}

/// 远端文件元数据
class RemoteFile {
  final String path;
  final int size;
  final DateTime lastModified;
  final String? etag;

  const RemoteFile({
    required this.path,
    required this.size,
    required this.lastModified,
    required this.etag,
  });
}

/// ETag 不匹配（HTTP 412）
class ETagMismatchException implements Exception {
  final String path;
  final String? expected;
  final String? actual;
  ETagMismatchException({required this.path, this.expected, this.actual});

  @override
  String toString() =>
      'ETagMismatchException(path: $path, expected: $expected, actual: $actual)';
}

/// 远端文件不存在（HTTP 404 等价语义）
class RemoteFileNotFoundException implements Exception {
  final String path;
  RemoteFileNotFoundException(this.path);

  @override
  String toString() => 'RemoteFileNotFoundException: $path';
}

/// 同步后端抽象接口
///
/// 同步协调器 [SyncService] 通过此接口与远端通信。
/// 实现类：[WebDAVBackend]（生产）、`LocalBackend`（测试）。
abstract class SyncBackend {
  /// 校验凭据。失败抛 [Exception]。
  Future<void> authenticate(Credentials creds);

  /// 列出目录下的文件（不含子目录递归）。
  Future<List<RemoteFile>> listDir(String path);

  /// 下载文件原始字节。
  ///
  /// 文件不存在抛 [RemoteFileNotFoundException]。
  Future<Uint8List> download(String path);

  /// 上传文件。
  ///
  /// [ifMatchEtag] 提供时，作为乐观锁：
  /// - 若文件已存在且 etag 与 [ifMatchEtag] 不匹配，抛 [ETagMismatchException]
  /// - 若文件不存在（首次上传），**视为匹配通过**，不抛异常
  /// - 若文件不存在但需要"必须更新而非创建"的语义，调用方应先 [exists] 校验
  ///
  /// 返回新的 etag。
  Future<String> upload(
    String path,
    Uint8List bytes, {
    String? ifMatchEtag,
  });

  /// 删除文件。文件不存在视为成功。
  Future<void> delete(String path);

  /// 创建目录。已存在视为成功。
  Future<void> mkcol(String path);

  /// 文件是否存在。
  Future<bool> exists(String path);
}
