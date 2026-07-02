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
  @Deprecated('由 AssetRepository.save 取代，2026-07-02 起停用。保留只为编译兼容。')
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
  @Deprecated('由 NoteStorageService.deleteNote 内部维护引用计数取代，2026-07-02 起停用。保留只为编译兼容。')
  Future<void> deleteImagesForNote(String noteId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/images/$noteId');
    if (imageDir.existsSync()) {
      await imageDir.delete(recursive: true);
    }
  }

  /// 删除单个图片文件
  @Deprecated('由 AssetRepository 配合引用计数取代，2026-07-02 起停用。保留只为编译兼容。')
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

  /// 列出指定笔记的所有图片文件路径
  Future<List<String>> listAssets(String noteId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/images/$noteId');
    if (!imageDir.existsSync()) return [];
    return imageDir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .toList();
  }
}
