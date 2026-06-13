import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 视频存储服务
///
/// 负责视频文件的保存、读取和清理。
/// 视频保存在 {appDir}/videos/{noteId}/ 目录下。
class VideoStorageService {
  /// 保存视频到文件系统
  ///
  /// [videoBytes] 视频二进制数据
  /// [noteId] 笔记 ID，用于创建子目录
  /// [extension] 文件扩展名，默认 mp4
  ///
  /// 返回视频文件的完整路径。
  Future<String> saveVideo(
    Uint8List videoBytes,
    String noteId, {
    String extension = 'mp4',
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${appDir.path}/videos/$noteId');
    if (!videoDir.existsSync()) {
      videoDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${videoDir.path}/$timestamp.$extension';
    final file = File(filePath);
    await file.writeAsBytes(videoBytes);

    return filePath;
  }

  /// 删除笔记关联的所有视频
  Future<void> deleteVideosForNote(String noteId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${appDir.path}/videos/$noteId');
    if (videoDir.existsSync()) {
      await videoDir.delete(recursive: true);
    }
  }

  /// 删除单个视频文件及其缩略图
  Future<void> deleteVideo(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
    // 同时删除对应的缩略图
    final thumbPath = _deriveThumbnailPath(filePath);
    if (thumbPath != null) {
      final thumbFile = File(thumbPath);
      if (thumbFile.existsSync()) {
        await thumbFile.delete();
      }
    }
  }

  /// 生成视频缩略图
  ///
  /// 使用 media_kit Player 的 screenshot API 截取视频帧。
  /// 返回缩略图文件的绝对路径，失败时返回 null。
  Future<String?> generateThumbnail(
    String source,
    String noteId, {
    int seekMs = 0,
  }) async {
    if (kIsWeb) return null;

    Player? player;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final videoDir = Directory('${appDir.path}/videos/$noteId');
      if (!videoDir.existsSync()) {
        videoDir.createSync(recursive: true);
      }

      // 推导缩略图文件名
      final videoFileName =
          File(source).uri.pathSegments.lastOrNull ?? 'video';
      final baseName = videoFileName.contains('.')
          ? videoFileName.substring(0, videoFileName.lastIndexOf('.'))
          : videoFileName;
      final thumbPath = '${videoDir.path}/thumb_$baseName.jpg';

      player = Player(
        configuration: const PlayerConfiguration(
          vo: 'libmpv',
        ),
      );
      // 附加 VideoController 以启用视频解码（默认 vid=no，需要 VC 才会设为 auto）
      VideoController(player);
      // 需要播放才能让 mpv 解码出第一帧
      await player.open(Media(source), play: true);

      // 等待视频参数可用（width 非空表示 mpv 已解析视频）
      int? width;
      try {
        width = await player.stream.width
            .firstWhere((w) => w != null && w > 0)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}

      if (width == null) {
        player.dispose();
        player = null;
        return null;
      }

      // 等待帧实际渲染（buffering 结束表示播放已开始）
      try {
        await player.stream.buffering
            .firstWhere((b) => b == false)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}

      // 短暂等待确保帧已合成
      await Future.delayed(const Duration(milliseconds: 200));

      final bytes = await player.screenshot(format: 'image/jpeg');
      player.dispose();
      player = null;

      if (bytes == null || bytes.isEmpty) return null;

      await File(thumbPath).writeAsBytes(bytes);
      return thumbPath;
    } catch (e) {
      return null;
    } finally {
      player?.dispose();
    }
  }

  /// 根据视频文件路径推导缩略图路径
  String? _deriveThumbnailPath(String videoFilePath) {
    try {
      final file = File(videoFilePath);
      final dir = file.parent.path;
      final fileName = file.uri.pathSegments.lastOrNull;
      if (fileName == null) return null;
      final baseName = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      return '$dir/thumb_$baseName.jpg';
    } catch (_) {
      return null;
    }
  }
}
