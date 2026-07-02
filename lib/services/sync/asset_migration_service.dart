// lib/services/sync/asset_migration_service.dart
// AssetMigrationService 需要读取 NoteStorageService.appDocumentsDirOverride
// （@visibleForTesting）以支持测试注入路径；这是测试基础设施的合理用法。
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/note.dart';
import '../note_storage_service.dart';
import 'asset_reference.dart';
import 'asset_repository.dart';

/// 历史附件一次性迁移服务。
///
/// 启动时调用 [migrateIfNeeded]：
/// 1. 检查 sync_state 表 migration_v2_done 标记
/// 2. 若未迁移且本地存在 images/ 或 videos/ 目录，跑迁移
/// 3. 拷贝（非移动）附件到 sync-assets/{hash}.{ext}
/// 4. 改写笔记 content 中绝对路径为 asset://
/// 5. 把原 images/ videos/ 目录重命名为 _migrated_backup
/// 6. 写完成标记
///
/// 迁移是幂等的——中途失败不写完成标记，下次启动重试。
class AssetMigrationService {
  final AssetRepository repo;
  final NoteStorageService storage;

  AssetMigrationService({required this.repo, required this.storage});

  Future<void> migrateIfNeeded() async {
    final done = (await storage.getSyncState('migration_v2_done')).data;
    if (done == '1') return;

    final appDirPath = storage.appDocumentsDirOverride ??
        (await getApplicationDocumentsDirectory()).path;

    final imagesDir = Directory('$appDirPath/images');
    final videosDir = Directory('$appDirPath/videos');
    final hasImages = imagesDir.existsSync();
    final hasVideos = videosDir.existsSync();

    if (!hasImages && !hasVideos) {
      await storage.setSyncState('migration_v2_done', '1');
      return;
    }

    // hash → ext 映射，给后续笔记内容改写用
    final pathToAsset = <String, AssetReference>{};

    // 1. 扫描并拷贝图片
    if (hasImages) {
      await for (final noteDir in imagesDir.list()) {
        if (noteDir is! Directory) continue;
        await for (final entity in noteDir.list()) {
          if (entity is! File) continue;
          final ref = await _copyFile(entity);
          if (ref != null) {
            pathToAsset[entity.path] = ref;
          }
        }
      }
    }

    // 2. 扫描并拷贝视频（含缩略图）
    if (hasVideos) {
      await for (final noteDir in videosDir.list()) {
        if (noteDir is! Directory) continue;
        await for (final entity in noteDir.list()) {
          if (entity is! File) continue;
          final ref = await _copyFile(entity);
          if (ref != null) {
            pathToAsset[entity.path] = ref;
          }
        }
      }
    }

    // 3. 改写所有笔记 content
    await _rewriteNotes(pathToAsset);

    // 4. 重命名原目录为 _migrated_backup（清理可能的部分迁移残留）
    if (hasImages) {
      final backup = Directory('$appDirPath/images_migrated_backup');
      if (backup.existsSync()) {
        backup.deleteSync(recursive: true);
      }
      await imagesDir.rename('$appDirPath/images_migrated_backup');
    }
    if (hasVideos) {
      final backup = Directory('$appDirPath/videos_migrated_backup');
      if (backup.existsSync()) {
        backup.deleteSync(recursive: true);
      }
      await videosDir.rename('$appDirPath/videos_migrated_backup');
    }

    // 5. 写完成标记
    await storage.setSyncState('migration_v2_done', '1');
  }

  /// 拷贝单个文件到 sync-assets/，返回对应的 AssetReference。
  /// 文件读取失败返回 null。
  Future<AssetReference?> _copyFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = _extOf(file.path);
      return await repo.save(bytes, ext);
    } catch (e) {
      debugPrint('[migration] skip ${file.path}: $e');
      return null;
    }
  }

  /// 加载所有笔记，对每篇 content 做路径替换：
  /// 把所有已知的绝对路径（pathToAsset 的 key）替换为对应的 asset:// URL。
  ///
  /// 路径在笔记里可能以不同斜杠形式出现（Windows 反斜杠 / 正斜杠 / 混合，
  /// 以及 JSON 字符串里反斜杠被转义成 `\\` 的情况），不能简单做字面 replaceAll。
  /// 这里用 [RegExp] 构造一个忽略斜杠方向、并兼容 JSON 转义的匹配模式。
  Future<void> _rewriteNotes(Map<String, AssetReference> pathToAsset) async {
    if (pathToAsset.isEmpty) return;
    final notes = await storage.loadAllNotesIncludingDeleted();
    if (!notes.success) {
      throw StateError('migration aborted: load notes failed - ${notes.error}');
    }
    final all = notes.data ?? const <Note>[];
    for (final note in all) {
      var content = note.content;
      var changed = false;
      for (final entry in pathToAsset.entries) {
        final pattern = _pathPattern(entry.key);
        final newContent = content.replaceAllMapped(pattern, (_) => entry.value.uri);
        if (!identical(newContent, content) && newContent != content) {
          content = newContent;
          changed = true;
        }
      }
      if (changed) {
        await storage.saveNote(note.copyWith(
          content: content,
          updatedAt: DateTime.now(),
          syncStatus: SyncStatus.dirty,
        ));
      }
    }
  }

  /// 把路径转成正则：每个 `\` 或 `/` 匹配 `[\\/]+`（一到多个任意斜杠）。
  /// 这样既能容忍 Windows / Unix 斜杠差异，也能匹配 JSON 中 `\\` 双写形式。
  RegExp _pathPattern(String path) {
    final escaped = path.split('').map((c) {
      if (c == '\\' || c == '/') return r'[\\/]+';
      // 转义其他正则元字符
      if (RegExp(r'[.*+?^${}()|[\]]').hasMatch(c)) return '\\$c';
      return c;
    }).join('');
    return RegExp(escaped);
  }

  String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'bin';
    return path.substring(dot + 1).toLowerCase();
  }
}
