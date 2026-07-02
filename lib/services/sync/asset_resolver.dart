import 'dart:io';

import '../note_storage_service.dart';
import 'asset_reference.dart';

/// 把 source 字段（可能是 asset://、http(s)://、file://、绝对路径）解析为
/// 渲染层可用的本地路径。
///
/// 协议非 asset://：原样返回，调用方自行处理（FileImage、NetworkImage 等）。
/// 协议是 asset:// 但本地无文件：返回 null，调用方应显示占位图并触发
/// [SyncService.pullMissingAssets] 后台拉取。
class AssetResolver {
  final NoteStorageService _storage;

  AssetResolver(this._storage);

  Future<String?> resolveLocalPath(String? source) async {
    if (source == null || source.isEmpty) return null;

    final ref = AssetReference.tryParse(source);
    if (ref == null) {
      // 非 asset://，原样返回
      return source;
    }

    final records = (await _storage.listSyncAssets())
        .data!
        .where((r) => r.hash == ref.hash)
        .toList();
    if (records.isEmpty) return null;
    final localPath = records.first.localPath;
    // 表里有记录但文件被外部清理：视为缺失，触发上层后台拉取
    if (!File(localPath).existsSync()) return null;
    return localPath;
  }
}
