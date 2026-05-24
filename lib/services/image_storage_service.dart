import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// 图片存储服务
///
/// 负责图片文件的保存、读取和清理。
/// 图片保存在 {appDir}/images/{noteId}/ 目录下。
class ImageStorageService {
  /// 保存图片到文件系统
  ///
  /// [imageBytes] 图片二进制数据
  /// [noteId] 笔记 ID，用于创建子目录
  /// [extension] 文件扩展名，默认 png
  ///
  /// 返回图片文件的完整路径。
  Future<String> saveImage(
    Uint8List imageBytes,
    String noteId, {
    String extension = 'png',
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/images/$noteId');
    if (!imageDir.existsSync()) {
      imageDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${imageDir.path}/$timestamp.$extension';
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);

    return filePath;
  }

  /// 删除笔记关联的所有图片
  Future<void> deleteImagesForNote(String noteId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/images/$noteId');
    if (imageDir.existsSync()) {
      await imageDir.delete(recursive: true);
    }
  }

  /// 删除单个图片文件
  Future<void> deleteImage(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// 获取图片文件
  File? getImageFile(String filePath) {
    final file = File(filePath);
    return file.existsSync() ? file : null;
  }
}
