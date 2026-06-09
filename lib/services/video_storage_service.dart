import 'dart:io';
import 'dart:typed_data';
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

  /// 删除笔记关联的所有视频
  Future<void> deleteVideosForNote(String noteId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${appDir.path}/videos/$noteId');
    if (videoDir.existsSync()) {
      await videoDir.delete(recursive: true);
    }
  }

  /// 删除单个视频文件
  Future<void> deleteVideo(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
