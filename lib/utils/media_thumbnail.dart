import 'dart:convert';

class MediaInfo {
  final String source;
  final bool isVideo;
  final String? thumbnail;

  const MediaInfo({required this.source, required this.isVideo, this.thumbnail});

  bool get isNetwork =>
      source.startsWith('http://') || source.startsWith('https://');
}

/// 从笔记 delta JSON 内容中提取第一个图片或视频的 source 路径。
/// 如果没有媒体则返回 null。
MediaInfo? extractFirstMedia(String content) {
  if (content.isEmpty) return null;
  try {
    final delta = jsonDecode(content) as List<dynamic>;
    for (final op in delta) {
      if (op is! Map<String, dynamic>) continue;
      final insert = op['insert'];
      if (insert is! Map<String, dynamic>) continue;

      // 检查图片
      final image = insert['image'];
      if (image is String) {
        final result = _parseMediaData(image);
        if (result != null) {
          return MediaInfo(source: result.source, isVideo: false);
        }
      }

      // 检查视频
      final video = insert['video'];
      if (video is String) {
        final result = _parseMediaData(video);
        if (result != null) {
          return MediaInfo(
            source: result.source,
            isVideo: true,
            thumbnail: result.thumbnail,
          );
        }
      }
    }
    return null;
  } catch (e) {
    return null;
  }
}

_MediaData? _parseMediaData(String rawData) {
  try {
    final json = jsonDecode(rawData) as Map<String, dynamic>;
    final source = json['source'] as String?;
    if (source == null) return null;
    return _MediaData(
      source: source,
      thumbnail: json['thumbnail'] as String?,
    );
  } catch (_) {
    // 旧格式：rawData 直接就是路径
    return rawData.isNotEmpty ? _MediaData(source: rawData) : null;
  }
}

class _MediaData {
  final String source;
  final String? thumbnail;

  const _MediaData({required this.source, this.thumbnail});
}
