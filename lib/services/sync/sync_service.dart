import 'dart:async';
import 'dart:convert';
import 'dart:io';

// SyncService._getAssetsDir 需要读取 NoteStorageService.appDocumentsDirOverride
// （@visibleForTesting）以支持测试注入路径；这是测试基础设施的合理用法。
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../note_storage_service.dart';
import '../../models/note.dart';
import 'asset_reference.dart';
import 'conflict_resolver.dart';
import 'manifest_cache.dart';
import 'sync_backend.dart';
import 'sync_config.dart';
import 'sync_state.dart';
import 'webdav/webdav_backend.dart';

/// 简易路径拼接器（始终用 `/` 分隔，避免 Windows `package:path` 返回 `\`）
class _PathUtil {
  static String join(String a, String b) {
    if (a.endsWith('/')) return '$a$b';
    return '$a/$b';
  }
}

/// 同步协调器
///
/// 编排 Pull → Push 流程。除串行化锁外无状态：所有持久状态在
/// [NoteStorageService] / 远端 manifest 中。
///
/// 调用方契约：
/// - [syncOnce] 可被并发调用（编辑防抖、启动、前台恢复等），内部自动串行化
/// - 同步顺序：先拉远端变更到本地（包括冲突解决），再推送本地 dirty
/// - 软删除（墓碑）通过 Note.deletedAt 字段传播
class SyncService {
  final NoteStorageService storage;
  final SyncBackend backend;
  final SyncStateManager state;

  /// 可变：用户可在设置页修改根目录后通过 [reconfigure] 更新。
  String rootPath;

  Completer<void>? _runningLock;
  bool _pendingAnotherRun = false;

  SyncService({
    required this.storage,
    required this.backend,
    required this.state,
    required this.rootPath,
  });

  /// 运行时更新同步配置（baseUrl、凭据、根目录）。
  ///
  /// 必须在 SyncSettingsScreen 保存配置后调用——否则 SyncService 实例
  /// 持有的还是启动时固化的旧配置（特别是首次配置时 baseUrl 为空，
  /// 会触发 "No host specified in URI" 错误）。
  ///
  /// 当前实现仅支持 WebDAVBackend；其他后端类型需自行扩展。
  void reconfigure(SyncConfig config) {
    if (backend is WebDAVBackend) {
      (backend as WebDAVBackend).reconfigure(
        baseUrl: config.webdavUrl,
        credentials: config.toCredentials(),
      );
    }
    rootPath = config.webdavRootPath;
  }

  /// 最小连通性探测：仅做一次只读请求验证地址+凭据，无副作用。
  ///
  /// 给设置页"测试连接"按钮调用——避免为了测连接就触发完整同步
  /// （后者会建目录、上传下载、可能改数据，且错误链路长难诊断）。
  ///
  /// 失败抛带可读中文诊断的 [Exception]。
  Future<void> testConnection() async {
    await backend.testConnection(rootPath);
  }

  /// 触发一次同步。多次并发调用自动串行化。
  Future<void> syncOnce() async {
    if (_runningLock != null) {
      // 已有同步在跑，标记需要再跑一次
      _pendingAnotherRun = true;
      await _runningLock!.future;
      return;
    }
    final completer = Completer<void>();
    _runningLock = completer;

    try {
      await _doSync();
    } finally {
      final pending = _pendingAnotherRun;
      _pendingAnotherRun = false;
      _runningLock = null;
      completer.complete();
      if (pending) {
        // 防止无限递归：用 scheduleMicrotask
        scheduleMicrotask(() => syncOnce());
      }
    }
  }

  Future<void> _doSync() async {
    state.markSyncing();
    try {
      await _ensureRootDirs();
      await _pullPhase();          // 1. 笔记先来（带 assets 引用清单）
      await _pushPhase();          // 2. 推笔记
      await pushPendingAssets();   // 3. 推 dirty 附件
      await pullMissingAssets();   // 4. 拉本地缺失附件
      await _updateManifest();
      state.markSuccess();
    } catch (e) {
      if (_isOfflineError(e)) {
        state.setOffline();
      } else {
        state.markError(e.toString());
      }
      rethrow; // 让调用方也能感知
    }
  }

  bool _isOfflineError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('timeout');
  }

  Future<void> _ensureRootDirs() async {
    await backend.mkcol(rootPath);
    await backend.mkcol(_PathUtil.join(rootPath, 'notes/'));
    await backend.mkcol(_PathUtil.join(rootPath, 'assets/'));
  }

  // ==================== Pull ====================

  Future<void> _pullPhase() async {
    final manifest = await _fetchManifest();
    final localResult = await storage.loadAllNotesIncludingDeleted();
    final localNotes = {
      for (final n in localResult.data ?? const <Note>[]) n.id: n,
    };

    for (final entry in manifest.notes.entries) {
      final path = entry.key;
      final meta = entry.value;
      if (ConflictResolver.isConflictFile(path)) continue;

      final noteId = _noteIdFromPath(path);
      final local = localNotes[noteId];

      if (local == null) {
        // 本地无 → 下载
        await _downloadAndApply(path, meta);
      } else if (local.syncStatus == SyncStatus.clean) {
        if (meta.needsDownload(localEtag: local.remoteEtag)) {
          await _downloadAndApply(path, meta);
        }
      } else if (local.syncStatus == SyncStatus.dirty &&
          meta.etag != local.remoteEtag) {
        // 冲突
        await _handleConflict(local, path, meta);
      }
    }

    // 反向：本地 clean 且远端没了 → 软删本地（保留墓碑以备传播）
    //
    // 用 id 比较而不是 path 比较：PROPFIND 返回的 href 是 host 绝对路径，
    // 可能含共享名前缀（如 `/nvme12-xxx/notes-app/...`），而 _pathFromNoteId
    // 生成的是相对 rootPath 的子路径（如 `/notes-app/...`），形式不一致会让
    // containsKey 永远 false，所有本地 clean 笔记被错误软删。
    final remoteNoteIds = <String>{};
    for (final path in manifest.notes.keys) {
      if (ConflictResolver.isConflictFile(path)) continue;
      final id = _noteIdFromPath(path);
      if (id.isNotEmpty) remoteNoteIds.add(id);
    }

    for (final local in localNotes.values) {
      if (local.syncStatus != SyncStatus.clean) continue;
      if (local.deletedAt != null) continue; // 已是墓碑
      if (!remoteNoteIds.contains(local.id)) {
        final tombstone = local.copyWith(
          deletedAt: DateTime.now(),
          syncStatus: SyncStatus.dirty,
          updatedAt: DateTime.now(),
        );
        await storage.saveNoteFromSync(tombstone);
      }
    }
  }

  Future<void> _downloadAndApply(String path, ManifestEntry meta) async {
    final bytes = await backend.download(path);
    final note = _decodeNote(bytes, expectedEtag: meta.etag);
    if (note == null) return;
    await storage.saveNoteFromSync(note.copyWith(syncStatus: SyncStatus.clean));
  }

  Future<void> _handleConflict(
      Note local, String remotePath, ManifestEntry remoteMeta) async {
    final bytes = await backend.download(remotePath);
    final remote = _decodeNote(bytes, expectedEtag: remoteMeta.etag);
    if (remote == null) return;

    final resolution = ConflictResolver.resolve(
      localUpdatedAt: local.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );

    if (resolution == ConflictResolution.keepLocal) {
      // 旧远程另存为冲突副本
      await backend.upload(
        ConflictResolver.conflictFilename(
          notePath: remotePath,
          timestamp: DateTime.now(),
        ),
        bytes,
      );
      // 本地覆盖远程
      final newEtag = await backend.upload(
        remotePath,
        _encodeNote(local),
        ifMatchEtag: remoteMeta.etag,
      );
      await storage.saveNoteFromSync(local.copyWith(
        syncStatus: SyncStatus.clean,
        remoteEtag: newEtag,
      ));
    } else {
      // 保留远程：本地版本另存为副本（也上传到远端便于跨设备可见）
      await backend.upload(
        ConflictResolver.conflictFilename(
          notePath: remotePath,
          timestamp: DateTime.now(),
        ),
        _encodeNote(local),
      );
      await storage.saveNoteFromSync(remote.copyWith(
        syncStatus: SyncStatus.clean,
        remoteEtag: remoteMeta.etag,
      ));
    }
  }

  // ==================== Push ====================

  Future<void> _pushPhase() async {
    final dirtyNotes =
        (await storage.loadNotesBySyncStatus(SyncStatus.dirty)).data ?? [];
    for (final note in dirtyNotes) {
      try {
        final path = _pathFromNoteId(note.id);
        // 文本笔记与墓碑都直接上传（资源同步留给任务 9）
        final newEtag = await backend.upload(
          path,
          _encodeNote(note),
          ifMatchEtag: note.remoteEtag,
        );
        await storage.saveNoteFromSync(note.copyWith(
          syncStatus: SyncStatus.clean,
          remoteEtag: newEtag,
        ));
      } on ETagMismatchException {
        // race condition：pull 后 push 前远端被改
        final manifest = await _fetchManifest();
        final path = _pathFromNoteId(note.id);
        final meta = manifest.notes[path];
        if (meta != null) {
          await _handleConflict(note, path, meta);
        }
      } catch (e) {
        debugPrint('push note ${note.id} failed: $e');
      }
    }
  }

  // ==================== Assets ====================

  /// 推送所有 dirty 状态的资源到远端
  Future<void> pushPendingAssets() async {
    final assets = (await storage.listSyncAssets()).data ?? const <SyncAssetRecord>[];
    for (final asset in assets) {
      if (asset.syncStatus != SyncStatus.dirty) continue;
      // refCount=0 表示本地无引用——按 spec 决策表"资源 GC"行：
      // 不 push 远端、保留 dirty 状态等 cleanupOrphanAssets 清理本地表与文件
      // （远端文件按设计意图保留以备其他设备引用）。
      if (asset.refCount <= 0) continue;

      final remotePath = _PathUtil.join(
          rootPath, 'assets/${asset.hash}.${asset.ext}');
      final exists = await backend.exists(remotePath);
      if (exists) {
        // 远端已有（哈希相同）→ 跳过
        await storage.upsertSyncAsset(
          hash: asset.hash,
          ext: asset.ext,
          localPath: asset.localPath,
          remoteEtag: asset.remoteEtag,
          syncStatus: SyncStatus.clean,
          refCount: asset.refCount,
        );
        continue;
      }

      try {
        final bytes = await File(asset.localPath).readAsBytes();
        final etag = await backend.upload(remotePath, bytes);
        await storage.upsertSyncAsset(
          hash: asset.hash,
          ext: asset.ext,
          localPath: asset.localPath,
          remoteEtag: etag,
          syncStatus: SyncStatus.clean,
          refCount: asset.refCount,
        );
      } catch (e) {
        debugPrint('push asset ${asset.hash} failed: $e');
      }
    }
  }

  /// 拉取远端附件到本地。
  ///
  /// [hashFilter] 非空时只拉指定 hash 集合（用于渲染层按需拉取）；为空时
  /// 全量扫描远端 assets/ 目录、拉取本地缺失的所有资源。
  Future<void> pullMissingAssets({Set<String>? hashFilter}) async {
    final localAssets = {
      for (final a in (await storage.listSyncAssets()).data ?? const <SyncAssetRecord>[])
        a.hash: a,
    };

    final candidates = <RemoteFile>[];
    if (hashFilter == null || hashFilter.isEmpty) {
      candidates.addAll(
        await backend.listDir(_PathUtil.join(rootPath, 'assets/')),
      );
    } else {
      // 仅探测 hashFilter 中的文件：直接 download（不存在会被 backend 抛错，捕获跳过）
      for (final hash in hashFilter) {
        if (localAssets.containsKey(hash)) continue;
        // 我们不知道 ext，按常见扩展名依次探测；命中即加入 candidates
        for (final ext in const ['png', 'jpg', 'jpeg', 'mp4', 'mov']) {
          final path = _PathUtil.join(rootPath, 'assets/$hash.$ext');
          if (await backend.exists(path)) {
            candidates.add(RemoteFile(
              path: path,
              size: 0,
              lastModified: DateTime.now(),
              etag: null,
            ));
            break;
          }
        }
      }
    }

    for (final f in candidates) {
      final basename = f.path.split('/').last;
      final dot = basename.lastIndexOf('.');
      final hash = dot > 0 ? basename.substring(0, dot) : basename;
      final ext = dot > 0 ? basename.substring(dot + 1) : 'bin';
      if (localAssets.containsKey(hash)) continue;

      try {
        final bytes = await backend.download(f.path);
        final localPath = await _saveAssetLocally(hash, ext, bytes);
        await storage.upsertSyncAsset(
          hash: hash,
          ext: ext,
          localPath: localPath,
          remoteEtag: f.etag,
          syncStatus: SyncStatus.clean,
          refCount: 0, // 引用计数由调用方 saveNote 维护
        );
      } catch (e) {
        debugPrint('pull asset $hash failed: $e');
      }
    }
  }

  Future<String> _saveAssetLocally(
      String hash, String ext, Uint8List bytes) async {
    final dir = await _getAssetsDir();
    final path = _PathUtil.join(dir.path, '$hash.$ext');
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// 清理本地 sync_assets 表中 refCount=0 的记录（不删远程）。
  /// 同步删除 sync-assets/{hash}.{ext} 本地文件，避免磁盘堆积无引用附件。
  Future<void> cleanupOrphanAssets() async {
    final assets =
        (await storage.listSyncAssets()).data ?? const <SyncAssetRecord>[];
    final dir = await _getAssetsDir();
    for (final asset in assets) {
      if (asset.refCount <= 0) {
        final path = _PathUtil.join(dir.path, '${asset.hash}.${asset.ext}');
        try {
          final file = File(path);
          if (file.existsSync()) await file.delete();
        } catch (e) {
          debugPrint('[cleanup] failed to delete $path: $e');
        }
        await storage.deleteSyncAsset(asset.hash);
      }
    }
  }

  Future<Directory> _getAssetsDir() async {
    final String appDirPath;
    if (storage.appDocumentsDirOverride != null) {
      appDirPath = storage.appDocumentsDirOverride!;
    } else {
      appDirPath = (await getApplicationDocumentsDirectory()).path;
    }
    final dir = Directory(_PathUtil.join(appDirPath, 'sync-assets'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  // ==================== Conflict 冲突副本管理 ====================

  /// 列出远端所有冲突副本
  Future<List<RemoteFile>> listConflictFiles() async {
    final files = await backend.listDir(_PathUtil.join(rootPath, 'notes/'));
    return files
        .where((f) => ConflictResolver.isConflictFile(f.path))
        .toList();
  }

  /// 把冲突副本下载到本地（用户决定如何合并）
  Future<void> downloadConflictToDesktop(RemoteFile file) async {
    final bytes = await backend.download(file.path);
    // 简化：保存到 app docs dir 的 conflicts 子目录
    final dir = await _getAssetsDir();
    final conflictDir = Directory(_PathUtil.join(dir.parent.path, 'conflicts'));
    if (!conflictDir.existsSync()) {
      conflictDir.createSync(recursive: true);
    }
    final name = file.path.split('/').last;
    await File(_PathUtil.join(conflictDir.path, name)).writeAsBytes(bytes);
  }

  /// 删除远端冲突副本
  Future<void> deleteConflictFile(RemoteFile file) async {
    await backend.delete(file.path);
  }

  // ==================== Manifest ====================

  Future<ManifestData> _fetchManifest() async {
    // 当前实现：每次都通过 listDir 重建。
    //
    // manifest.json 文件作为缓存是同步流程的设计意图，但本地测试场景下
    // 会有"另一设备直接覆盖文件、不动 manifest"的情况。如果信任缓存
    // manifest 会导致漏更新。
    //
    // 任务 10 WebDAVBackend 接入后可改为：先尝试 PROPFIND（一次请求
    // 同时拿到所有 etag），过期则重建 manifest。
    return _buildManifestFromListing();
  }

  Future<ManifestData> _buildManifestFromListing() async {
    final files = await backend.listDir(_PathUtil.join(rootPath, 'notes/'));
    final notes = <String, ManifestEntry>{};
    for (final f in files) {
      if (ConflictResolver.isConflictFile(f.path)) continue;
      notes[f.path] = ManifestEntry(
        etag: f.etag ?? '',
        size: f.size,
        hash: '',
        updatedAt: f.lastModified,
      );
    }
    return ManifestData(
      version: 1,
      generatedAt: DateTime.now(),
      notes: notes,
      assets: const {},
    );
  }

  Future<void> _updateManifest() async {
    final manifest = await _buildManifestFromListing();
    await backend.upload(
      _PathUtil.join(rootPath, 'manifest.json'),
      Uint8List.fromList(utf8.encode(manifest.encode())),
    );
  }

  // ==================== 编解码 ====================

  String _pathFromNoteId(String id) => _PathUtil.join(rootPath, 'notes/$id.json');

  String _noteIdFromPath(String path) {
    final basename = path.split('/').last;
    final dot = basename.lastIndexOf('.');
    return dot > 0 ? basename.substring(0, dot) : basename;
  }

  Uint8List _encodeNote(Note note) {
    final hashes = AssetReference.scanHashes(note.content);
    final assets = <Map<String, dynamic>>[
      for (final h in hashes) {'hash': h, 'ext': '', 'kind': 'unknown'}
    ];
    // 注意 ext/kind 仅作信息性字段（解码端不强校验），实际渲染时按 hash 从
    // sync_assets 表反查 ext。这里写空字符串避免在 _encodeNote 里二次查表。
    // 后续 _decodeNote 处理 assets 字段时只关心 hash 是否在 sync_assets 表里。

    final map = <String, dynamic>{
      'schema': 2,
      'id': note.id,
      'title': note.title,
      'content': note.content,
      'type': note.type,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
      'assets': assets,
      'deletedAt': note.deletedAt?.toIso8601String(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  Note? _decodeNote(List<int> bytes, {String? expectedEtag}) {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      // schema=1（旧远端笔记）和 schema=2（新版）都按相同字段读取；assets 字段
      // 暂不在解码时强校验——引用计数维护由 NoteStorageService.saveNote 触发，
      // 同步路径下的笔记先入库，后续打开渲染时才触发 pullMissingAssets。
      return Note(
        id: map['id'] as String,
        title: (map['title'] ?? '') as String,
        content: (map['content'] ?? '') as String,
        type: (map['type'] ?? 'rich_text') as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
        syncStatus: SyncStatus.clean,
        remoteEtag: expectedEtag,
        deletedAt: map['deletedAt'] != null
            ? DateTime.parse(map['deletedAt'] as String)
            : null,
      );
    } catch (e) {
      debugPrint('decode note failed: $e');
      return null;
    }
  }

  /// 计算字节流的 SHA-256（用于资源去重 key）
  static String sha256Hex(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }
}
