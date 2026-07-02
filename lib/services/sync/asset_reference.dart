/// asset:// 协议资源引用。
///
/// 笔记内容里图片/视频的 source 改用 [uri] 表示（如 `asset://a3f5.png`），
/// 跨设备稳定。各设备由 AssetResolver 负责把 uri 解析为本地实际路径。
class AssetReference {
  final String hash;
  final String ext;

  const AssetReference(this.hash, this.ext);

  /// 资源的 asset:// URI。
  String get uri => 'asset://$hash.$ext';

  /// 扫描文本中所有 asset:// 引用，返回 hash 集合。
  ///
  /// 用于 _encodeNote 输出 assets 字段、NoteStorageService 维护引用计数。
  /// Quill Delta 的 image/video embed 把 source 放在 JSON 里：
  ///   {"insert":{"embed":{"type":"image","source":"asset://HASH.ext"}}}
  /// 或简化形式：
  ///   {"insert":{"image":"asset://HASH.ext"}}
  /// 直接用正则扫整段 content 字符串最稳健——不依赖具体 schema。
  static Set<String> scanHashes(String content) {
    final result = <String>{};
    final regex = RegExp(r'asset://([a-f0-9]{40,128})\.([a-zA-Z0-9]+)');
    for (final m in regex.allMatches(content)) {
      result.add(m.group(1)!);
    }
    return result;
  }

  /// 解析 asset:// URI；协议不匹配或格式错误返回 null。
  ///
  /// 非 asset:// 输入（http://、file://、绝对本地路径、相对路径）一律返回 null，
  /// 调用方据此走原有逻辑。
  static AssetReference? tryParse(String? source) {
    if (source == null || source.isEmpty) return null;
    if (!source.startsWith('asset://')) return null;

    final body = source.substring('asset://'.length);
    if (body.isEmpty) return null;

    final dot = body.lastIndexOf('.');
    if (dot <= 0 || dot == body.length - 1) return null;

    return AssetReference(body.substring(0, dot), body.substring(dot + 1));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetReference && hash == other.hash && ext == other.ext;

  @override
  int get hashCode => Object.hash(hash, ext);

  @override
  String toString() => 'AssetReference($uri)';
}
