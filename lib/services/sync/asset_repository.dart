import 'dart:io';
import 'dart:typed_data';

// AssetRepository 需要读取 NoteStorageService.appDocumentsDirOverride
// （@visibleForTesting）以支持测试注入路径；这是测试基础设施的合理用法。
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/note.dart';
import '../note_storage_service.dart';
import 'asset_reference.dart';

/// 附件统一存取入口。
///
/// 负责把字节流落地为 `sync-assets/{hash}.{ext}` 文件、维护 [sync_assets] 表
/// 记录与引用计数。同一哈希只存一份（去重）。引用计数由调用方
/// （[NoteStorageService.saveNote/deleteNote]）按笔记内容 diff 维护。
///
/// 不直接负责同步——同步由 [SyncService] 调用 [NoteStorageService.listSyncAssets]
/// 触发 push/pull assets 完成。
class AssetRepository {
  final NoteStorageService _storage;

  AssetRepository(this._storage);

  Future<Directory> _assetsDir() async {
    final appDirPath = _storage.appDocumentsDirOverride ??
        (await getApplicationDocumentsDirectory()).path;
    final dir = Directory('$appDirPath/sync-assets');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static String _sha256Hex(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// 保存字节流。同一哈希已存在则不重写文件、不调整 ref_count，但仍返回引用。
  /// 新写入的记录 sync_status=dirty（让同步推到远端）。
  Future<AssetReference> save(Uint8List bytes, String ext) async {
    final hash = _sha256Hex(bytes);
    final dir = await _assetsDir();
    final localPath = '${dir.path}/$hash.$ext';
    final file = File(localPath);

    final existing = (await _storage.listSyncAssets())
        .data!
        .where((r) => r.hash == hash)
        .toList();

    if (!file.existsSync()) {
      await file.writeAsBytes(bytes);
    }

    if (existing.isEmpty) {
      await _storage.upsertSyncAsset(
        hash: hash,
        ext: ext,
        localPath: localPath,
        syncStatus: SyncStatus.dirty,
        refCount: 0,
      );
    }

    return AssetReference(hash, ext);
  }

  /// 读字节流。本地文件不存在返回 null（即使表里有记录）。
  Future<Uint8List?> read(String hash) async {
    final records = (await _storage.listSyncAssets())
        .data!
        .where((r) => r.hash == hash)
        .toList();
    if (records.isEmpty) return null;
    final file = File(records.first.localPath);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  /// 把给定 hash 集合的 ref_count 各 +1。
  /// 同一 hash 在一次调用里多次出现按一次计（set 语义）。
  Future<void> incrementRefs(Set<String> hashes) async {
    if (hashes.isEmpty) return;
    final all = (await _storage.listSyncAssets()).data!;
    for (final hash in hashes) {
      final r = all.where((x) => x.hash == hash).toList();
      if (r.isEmpty) continue;
      final rec = r.first;
      await _storage.upsertSyncAsset(
        hash: rec.hash,
        ext: rec.ext,
        localPath: rec.localPath,
        remoteEtag: rec.remoteEtag,
        syncStatus: rec.syncStatus,
        refCount: rec.refCount + 1,
      );
    }
  }

  /// 把给定 hash 集合的 ref_count 各 -1，clamp 到 0。
  /// ref_count 减到 0 时 sync_status 标 dirty（让 cleanupOrphanAssets 处理）。
  Future<void> decrementRefs(Set<String> hashes) async {
    if (hashes.isEmpty) return;
    final all = (await _storage.listSyncAssets()).data!;
    for (final hash in hashes) {
      final r = all.where((x) => x.hash == hash).toList();
      if (r.isEmpty) continue;
      final rec = r.first;
      final newCount = rec.refCount > 0 ? rec.refCount - 1 : 0;
      await _storage.upsertSyncAsset(
        hash: rec.hash,
        ext: rec.ext,
        localPath: rec.localPath,
        remoteEtag: rec.remoteEtag,
        syncStatus: newCount == 0 ? SyncStatus.dirty : rec.syncStatus,
        refCount: newCount,
      );
    }
  }
}
