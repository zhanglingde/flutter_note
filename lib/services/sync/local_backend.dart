import 'package:flutter/foundation.dart';
import 'sync_backend.dart';

/// 内存实现的 SyncBackend，仅用于测试。
///
/// 文件路径作为 key 存于内存 Map。ETag 用上传时的字节内容哈希模拟。
/// 测试后端不验证凭据——任何 [Credentials] 都通过。
@visibleForTesting
class LocalBackend implements SyncBackend {
  final Map<String, _LocalFile> _files = {};
  final Set<String> _dirs = {};

  @override
  Future<void> authenticate(Credentials creds) async {
    // 测试后端接受任意凭据，无需保存。
  }

  @override
  Future<void> testConnection(String rootPath) async {
    // 内存后端永远"连通"，无需探测。
  }

  @override
  Future<void> mkcol(String path) async {
    _dirs.add(path);
  }

  @override
  Future<bool> exists(String path) async {
    return _files.containsKey(path) || _dirs.contains(path);
  }

  @override
  Future<String> upload(
    String path,
    Uint8List bytes, {
    String? ifMatchEtag,
  }) async {
    final existing = _files[path];
    if (ifMatchEtag != null && existing != null && existing.etag != ifMatchEtag) {
      throw ETagMismatchException(
        path: path,
        expected: ifMatchEtag,
        actual: existing.etag,
      );
    }
    final etag = '"${bytes.length}-${bytes.hashCode}"';
    _files[path] = _LocalFile(
      bytes: bytes,
      etag: etag,
      lastModified: DateTime.now(),
    );
    return etag;
  }

  @override
  Future<Uint8List> download(String path) async {
    final f = _files[path];
    if (f == null) throw RemoteFileNotFoundException(path);
    return f.bytes;
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }

  @override
  Future<List<RemoteFile>> listDir(String path) async {
    final prefix = path.endsWith('/') ? path : '$path/';
    final result = <RemoteFile>[];
    for (final entry in _files.entries) {
      if (entry.key.startsWith(prefix) &&
          !entry.key.substring(prefix.length).contains('/')) {
        result.add(RemoteFile(
          path: entry.key,
          size: entry.value.bytes.length,
          lastModified: entry.value.lastModified,
          etag: entry.value.etag,
        ));
      }
    }
    return result;
  }
}

class _LocalFile {
  final Uint8List bytes;
  final String etag;
  final DateTime lastModified;

  _LocalFile({
    required this.bytes,
    required this.etag,
    required this.lastModified,
  });
}
