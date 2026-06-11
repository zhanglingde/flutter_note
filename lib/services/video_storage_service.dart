import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

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

  /// 为视频生成 JPEG 缩略图
  ///
  /// [source] 视频源路径或 URL
  /// [videoFileName] 视频文件名（含扩展名）
  /// [noteId] 笔记 ID，用于确定缩略图存储目录
  ///
  /// 返回缩略图文件路径，失败时返回 null。
  Future<String?> generateThumbnail(String source, String videoFileName, String noteId) async {
    Player? player;
    try {
      player = Player();
      await player.open(Media(source), play: true);

      // 等待视频帧解码（width stream 触发表示元数据已加载）
      final completer = Completer<void>();
      final sub = player.stream.width.listen((w) {
        if (w != null && w > 0 && !completer.isCompleted) {
          completer.complete();
        }
      });
      await completer.future.timeout(const Duration(seconds: 5));
      await sub.cancel();

      // 等待帧渲染后暂停
      await Future.delayed(const Duration(milliseconds: 300));
      await player.pause();
      await player.seek(const Duration(milliseconds: 0));

      final jpegBytes = await player.screenshot(format: 'image/jpeg');
      if (jpegBytes == null) return null;

      final appDir = await getApplicationDocumentsDirectory();
      final videoDir = Directory('${appDir.path}/videos/$noteId');
      if (!videoDir.existsSync()) {
        videoDir.createSync(recursive: true);
      }

      final baseName = videoFileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      final thumbPath = '${videoDir.path}/thumb_$baseName.jpg';
      final file = File(thumbPath);
      await file.writeAsBytes(jpegBytes);

      return thumbPath;
    } catch (e) {
      debugPrint('generateThumbnail error: $e');
      return null;
    } finally {
      player?.dispose();
    }
  }

  /// 删除笔记关联的所有视频
  Future<void> deleteVideosForNote(String noteId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${appDir.path}/videos/$noteId');
    if (videoDir.existsSync()) {
      await videoDir.delete(recursive: true);
    }
  }

  /// 删除单个视频文件（同时删除关联缩略图）
  Future<void> deleteVideo(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
    final thumbPath = _getThumbnailPath(filePath);
    if (thumbPath != null) {
      final thumbFile = File(thumbPath);
      if (thumbFile.existsSync()) {
        await thumbFile.delete();
      }
    }
  }

  /// 根据视频文件路径推导缩略图路径
  ///
  /// 对于远程 URL（http/https）返回 null，不管理远程缩略图。
  static String? _getThumbnailPath(String videoPath) {
    if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
      return null;
    }
    final dir = videoPath.substring(0, videoPath.lastIndexOf('/'));
    final fileName = videoPath.substring(videoPath.lastIndexOf('/') + 1);
    final baseName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return '$dir/thumb_$baseName.jpg';
  }
}
