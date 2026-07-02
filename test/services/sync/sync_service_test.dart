import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/local_backend.dart';
import 'package:note/services/sync/sync_backend.dart';
import 'package:note/services/sync/sync_service.dart';
import 'package:note/services/sync/sync_state.dart';
import 'package:note/models/note.dart';

Note _makeNote(String id, {String title = 'T', DateTime? updatedAt}) {
  final now = updatedAt ?? DateTime.now();
  return Note(
    id: id,
    title: title,
    content: 'C',
    type: 'rich_text',
    createdAt: now,
    updatedAt: now,
  );
}

/// 工具：将一个笔记直接上传到 LocalBackend（绕过 SyncService，模拟"另一台设备同步过"）
Future<void> _seedRemote(LocalBackend backend, Note note) async {
  await backend.mkcol('/notes-app/');
  await backend.mkcol('/notes-app/notes/');
  await backend.upload(
    '/notes-app/notes/${note.id}.json',
    _encodeNote(note),
  );
}

Future<void> _overwriteRemote(LocalBackend backend, Note note) async {
  await backend.upload(
    '/notes-app/notes/${note.id}.json',
    _encodeNote(note),
  );
}

Uint8List _encodeNote(Note note) {
  final map = <String, dynamic>{
    'schema': 2,
    'id': note.id,
    'title': note.title,
    'content': note.content,
    'type': note.type,
    'createdAt': note.createdAt.toIso8601String(),
    'updatedAt': note.updatedAt.toIso8601String(),
    'assets': <Map<String, dynamic>>[],
    'deletedAt': note.deletedAt?.toIso8601String(),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(map)));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late NoteStorageService storage;
  late LocalBackend backend;
  late SyncStateManager state;
  late SyncService sync;
  // 保存 SyncService.appDocumentsDirOverride 指向的临时目录，用于 tearDown 清理。
  late Directory tmpAppDocsDir;

  setUp(() async {
    storage = NoteStorageService()
      ..dbPathOverride =
          (await Directory.systemTemp.createTemp('note_sync_service_test_')).path;
    await storage.init();
    // 为 SyncService 也准备一个独立的 app docs 目录，避免 pullMissingAssets
    // 写到真实设备目录（path_provider 在测试环境下未 mock）。
    tmpAppDocsDir = await Directory.systemTemp.createTemp('note_sync_appdocs_');
    // 复用 storage.appDocumentsDirOverride（SyncService._getAssetsDir 也读它），
    // 避免 SyncService 与 NoteStorageService 持有两份必须手动同步的字段。
    storage.appDocumentsDirOverride = tmpAppDocsDir.path;
    backend = LocalBackend();
    state = SyncStateManager();
    sync = SyncService(
      storage: storage,
      backend: backend,
      state: state,
      rootPath: '/notes-app/',
    );
    await backend.authenticate(
      const Credentials(username: 'u', password: 'p'),
    );
  });

  tearDown(() async {
    await storage.close();
    if (tmpAppDocsDir.existsSync()) {
      await tmpAppDocsDir.delete(recursive: true);
    }
  });

  test('first sync: local dirty note gets uploaded; remote manifest created',
      () async {
    final note = _makeNote('n1');
    await storage.saveNote(note.copyWith(syncStatus: SyncStatus.dirty));

    await sync.syncOnce();

    final files = await backend.listDir('/notes-app/notes/');
    expect(files.length, 1);
    expect(files.first.path, '/notes-app/notes/n1.json');

    final manifestExists = await backend.exists('/notes-app/manifest.json');
    expect(manifestExists, isTrue);

    final loaded = (await storage.loadNoteById('n1')).data!;
    expect(loaded.syncStatus, SyncStatus.clean);
    expect(loaded.remoteEtag, isNotNull);
  });

  test('pull: remote new note gets downloaded to local', () async {
    final remoteNote = _makeNote('remote-1');
    await _seedRemote(backend, remoteNote);

    await sync.syncOnce();

    final local = (await storage.loadNoteById('remote-1')).data;
    expect(local, isNotNull);
    expect(local!.title, 'T');
    expect(local.syncStatus, SyncStatus.clean);
  });

  test('pull: remote updated version overrides local clean', () async {
    final t1 = DateTime.utc(2026, 6, 14, 10);
    final t2 = DateTime.utc(2026, 6, 14, 12);
    final oldRemote = _makeNote('shared', updatedAt: t1);
    await _seedRemote(backend, oldRemote);

    await sync.syncOnce(); // 拉到 t1 版本

    // 远端被另一台设备更新
    await _overwriteRemote(
        backend, _makeNote('shared', updatedAt: t2).copyWith(title: 'updated'));

    await sync.syncOnce(); // 应拉到 t2 版本
    final local = (await storage.loadNoteById('shared')).data!;
    expect(local.title, 'updated');
  });

  test('conflict: local dirty + remote changed keeps newer + conflict copy',
      () async {
    final tOld = DateTime.utc(2026, 6, 14, 10);
    final tLocalNew = DateTime.utc(2026, 6, 14, 12);
    final tRemoteNew = DateTime.utc(2026, 6, 14, 14);

    // 初始同步，本地有 tOld 版本
    final initial = _makeNote('c1', updatedAt: tOld).copyWith(title: 'orig');
    await _seedRemote(backend, initial);
    await sync.syncOnce();

    // 本地修改为 tLocalNew（dirty）
    final localDirty = (await storage.loadNoteById('c1')).data!.copyWith(
        title: 'local-edit',
        updatedAt: tLocalNew,
        syncStatus: SyncStatus.dirty);
    await storage.saveNote(localDirty);

    // 同时远端被改到 tRemoteNew
    await _overwriteRemote(
        backend,
        _makeNote('c1', updatedAt: tRemoteNew)
            .copyWith(title: 'remote-edit'));

    await sync.syncOnce();

    // 远程更新（tRemoteNew > tLocalNew）→ 保留远程，本地存为副本
    final local = (await storage.loadNoteById('c1')).data!;
    expect(local.title, 'remote-edit');

    // 应该有一个冲突副本文件
    final allFiles = await backend.listDir('/notes-app/notes/');
    final conflictFiles =
        allFiles.where((f) => f.path.contains('__conflict-')).toList();
    expect(conflictFiles.length, 1);
  });

  test('tombstone: remote deletion propagates to local', () async {
    final note = _makeNote('shared');
    await _seedRemote(backend, note);
    await sync.syncOnce();

    // 模拟另一端删除（推送了墓碑）
    final tombstone = _makeNote('shared').copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _overwriteRemote(backend, tombstone);

    await sync.syncOnce();

    final local = (await storage.loadAllNotesIncludingDeleted()).data!
        .firstWhere((n) => n.id == 'shared');
    expect(local.deletedAt, isNotNull);
  });

  test('serialization: concurrent triggers do not run in parallel', () async {
    final note = _makeNote('serial');
    await storage.saveNote(note.copyWith(syncStatus: SyncStatus.dirty));

    // 同时触发两次
    final f1 = sync.syncOnce();
    final f2 = sync.syncOnce();
    await Future.wait([f1, f2]);

    // 应只产生一次写入（manifest 计数 1）
    final files = await backend.listDir('/notes-app/notes/');
    expect(files.where((f) => f.path.contains('serial')).length, 1);
  });

  // ============================================================
  // I1: keepLocal 分支（local 更新或相等 → 本地保留 + 覆盖远端 + 旧远程另存为副本）
  // ============================================================
  test('conflict keepLocal: local newer preserves local and uploads remote as conflict copy',
      () async {
    final tOld = DateTime.utc(2026, 6, 14, 10);
    final tLocalNew = DateTime.utc(2026, 6, 14, 14);
    final tRemoteOld = DateTime.utc(2026, 6, 14, 12);

    // 初始同步：本地有 tOld 版本
    final initial =
        _makeNote('c-local', updatedAt: tOld).copyWith(title: 'orig');
    await _seedRemote(backend, initial);
    await sync.syncOnce();

    // 本地修改为 tLocalNew（dirty，比远端新）
    final localDirty = (await storage.loadNoteById('c-local')).data!.copyWith(
        title: 'local-newer',
        updatedAt: tLocalNew,
        syncStatus: SyncStatus.dirty);
    await storage.saveNote(localDirty);

    // 同时远端被改到 tRemoteOld（比本地旧）
    await _overwriteRemote(backend,
        _makeNote('c-local', updatedAt: tRemoteOld).copyWith(title: 'remote-older'));

    await sync.syncOnce();

    // 本地更新（tLocalNew > tRemoteOld）→ 保留本地，覆盖远端
    final local = (await storage.loadNoteById('c-local')).data!;
    expect(local.title, 'local-newer');
    expect(local.syncStatus, SyncStatus.clean);

    // 应该有一个冲突副本文件（旧远程另存为副本）
    final allFiles = await backend.listDir('/notes-app/notes/');
    final conflictFiles =
        allFiles.where((f) => f.path.contains('__conflict-')).toList();
    expect(conflictFiles.length, 1);
  });

  // ============================================================
  // I2: push 阶段 ETagMismatchException 重处理路径
  // ============================================================
  // 真正触发 _pushPhase 内的 `on ETagMismatchException` 分支。
  //
  // 挑战：pull 阶段也会检测 etag 不匹配（dirty + 远端 etag 变 → pull 触发冲突），
  // 优先于 push。要触发 push 分支，需要让 pull 阶段认为 etag 一致，但 push 时
  // upload 抛 ETagMismatchException——这模拟"另一端在 pull 完成后、push 之前改了远端"。
  //
  // 实现：用一个包装 backend，让它的 listDir 返回的 etag 始终是"上次已知 etag"
  // （等于本地 remoteEtag），从而 pull 不触发冲突；同时让 upload 在 ifMatchEtag
  // 非空时强制抛 ETagMismatchException，从而 push 进入异常分支。
  test(
      'push: ETagMismatchException triggers conflict resolution (retry via _handleConflict)',
      () async {
    final tOld = DateTime.utc(2026, 6, 14, 10);
    final tLocalNew = DateTime.utc(2026, 6, 14, 14);
    final tRemoteOld = DateTime.utc(2026, 6, 14, 12);

    // 远端预置 tOld 版本
    await _seedRemote(
        backend, _makeNote('c-push', updatedAt: tOld).copyWith(title: 'orig'));

    // 同步一次让本地拿到 tOld 快照
    await sync.syncOnce();

    // 记录本地已知的 remoteEtag，作为 wrapper 的"上次已知 etag"
    final knownEtag =
        (await storage.loadNoteById('c-push')).data!.remoteEtag!;

    // 用一个包装 backend：listDir 始终返回 knownEtag（pull 不会发现冲突），
    // upload 在 ifMatchEtag 非空时抛 ETagMismatchException（push 阶段才触发）
    final hijacked = _PushConflictBackend(backend, frozenEtag: knownEtag);
    sync = SyncService(
      storage: storage,
      backend: hijacked,
      state: state,
      rootPath: '/notes-app/',
    );

    // 远端被另一端改到 tRemoteOld（但因为 wrapper 冻结了 etag，pull 看不到这变化）
    await _overwriteRemote(backend,
        _makeNote('c-push', updatedAt: tRemoteOld).copyWith(title: 'remote-older'));

    // 本地修改为 tLocalNew（dirty）
    final localDirty = (await storage.loadNoteById('c-push')).data!.copyWith(
        title: 'local-newer',
        updatedAt: tLocalNew,
        syncStatus: SyncStatus.dirty);
    await storage.saveNote(localDirty);

    await sync.syncOnce();

    // 验证 _handleConflict 被触发并按 LWW 处理（tLocalNew > tRemoteOld → keepLocal）
    final local = (await storage.loadNoteById('c-push')).data!;
    expect(local.title, 'local-newer');
    expect(local.syncStatus, SyncStatus.clean);

    // wrapper 必须确实触发了 push 阶段的 ETagMismatchException
    expect(hijacked.pushConflictTriggered, isTrue,
        reason: '_pushPhase 必须尝试过 upload 并收到 ETagMismatchException');

    // 应该有一个冲突副本
    final allFiles = await backend.listDir('/notes-app/notes/');
    expect(allFiles.where((f) => f.path.contains('__conflict-')).length, 1);
  });

  // ============================================================
  // I3: 反向软删（本地 clean + 远端文件彻底没了 → 本地变 dirty tombstone → push 推送墓碑）
  // ============================================================
  test('reverse tombstone: local clean + remote missing creates tombstone and pushes it',
      () async {
    // 初始：远端和本地都有
    final note = _makeNote('to-delete');
    await _seedRemote(backend, note);
    await sync.syncOnce();

    // 模拟远端文件被彻底删除（不是墓碑，是文件没了）
    await backend.delete('/notes-app/notes/to-delete.json');

    await sync.syncOnce();

    // 本地应该是墓碑（远端没了 → 软删本地 → push 推送墓碑 → 本地 clean）
    final local = (await storage.loadAllNotesIncludingDeleted()).data!
        .firstWhere((n) => n.id == 'to-delete');
    expect(local.deletedAt, isNotNull,
        reason: '反向软删应将本地标记为墓碑');

    // 远端应该有墓碑文件（push 阶段把墓碑推送到远端）
    // （如果反向软删没把墓碑标记为 dirty，push 阶段不会上传）
    final remoteFiles = await backend.listDir('/notes-app/notes/');
    final tombstoneFile =
        remoteFiles.where((f) => f.path.endsWith('to-delete.json')).toList();
    expect(tombstoneFile.length, 1,
        reason: 'push 阶段应将墓碑推送到远端');
    final remoteBytes = await backend.download('/notes-app/notes/to-delete.json');
    final remoteJson =
        jsonDecode(utf8.decode(remoteBytes)) as Map<String, dynamic>;
    expect(remoteJson['deletedAt'], isNotNull,
        reason: '推送的远端文件应为墓碑（deletedAt 非空）');
  });

  // ============================================================
  // 回归：极空间 NAS 等 PROPFIND 返回 host 绝对路径（含共享名前缀），
  // 与 _pathFromNoteId 生成的相对 rootPath 形式不一致。
  // 之前 bug：containsKey 永远 false → 所有本地 clean 笔记被错误软删。
  // 修复后：用 id 比较而非 path 比较，path 形式不一致不影响软删判定。
  // ============================================================
  test(
      'reverse tombstone: PROPFIND href with shared-folder prefix does not cause false local deletion',
      () async {
    final prefixedBackend =
        _PrefixedPathBackend(backend, prefix: '/nvme12-shared');
    sync = SyncService(
      storage: storage,
      backend: prefixedBackend,
      state: state,
      rootPath: '/notes-app/',
    );

    // 预置 note 到 inner backend（不带前缀，模拟 NAS 实际存储）
    final note = _makeNote('1780404559641');
    await _seedRemote(backend, note);

    await sync.syncOnce();

    // 验证：本地 note 没被错误软删
    final all = (await storage.loadAllNotesIncludingDeleted()).data!;
    final local = all.firstWhere((n) => n.id == '1780404559641');
    expect(local.deletedAt, isNull,
        reason:
            'PROPFIND href 含共享名前缀（与 _pathFromNoteId 形式不一致）不应导致本地被错误软删');
  });


  // ============================================================
  // 资源同步：内容寻址去重 + 孤儿资源 GC
  // ============================================================
  test('asset: same content uploads only once (dedup)', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final hash = SyncService.sha256Hex(bytes);

    // 创建临时文件作为 localPath
    final tmpDir = await Directory.systemTemp.createTemp('asset_test_');
    final tmpFile = File('${tmpDir.path}/a.png');
    await tmpFile.writeAsBytes(bytes);

    // 同一资源被两个笔记引用（refCount=2）
    await storage.upsertSyncAsset(
      hash: hash,
      ext: 'png',
      localPath: tmpFile.path,
      syncStatus: SyncStatus.dirty,
      refCount: 2,
    );

    await sync.pushPendingAssets();

    final assets = await backend.listDir('/notes-app/assets/');
    expect(assets.length, 1);
    expect(assets.first.path, '/notes-app/assets/$hash.png');

    // 清理临时文件
    await tmpDir.delete(recursive: true);
  });

  test('cleanupOrphanAssets removes assets with refCount=0 and deletes local file', () async {
    // 在 sync-assets/ 目录下放两个真实文件，仅一个 refCount=0
    final assetsDirPath = '${storage.appDocumentsDirOverride}/sync-assets';
    await Directory(assetsDirPath).create(recursive: true);
    final orphanFile = File('$assetsDirPath/h-orphan.png')..writeAsBytesSync([1, 2, 3]);
    final usedFile = File('$assetsDirPath/h-used.png')..writeAsBytesSync([4, 5, 6]);
    expect(orphanFile.existsSync(), isTrue);
    expect(usedFile.existsSync(), isTrue);

    await storage.upsertSyncAsset(
      hash: 'h-orphan',
      ext: 'png',
      localPath: orphanFile.path,
      syncStatus: SyncStatus.clean,
      refCount: 0,
    );
    await storage.upsertSyncAsset(
      hash: 'h-used',
      ext: 'png',
      localPath: usedFile.path,
      syncStatus: SyncStatus.clean,
      refCount: 1,
    );

    await sync.cleanupOrphanAssets();

    // 表记录只剩被引用的
    final assets = (await storage.listSyncAssets()).data!;
    expect(assets.map((a) => a.hash).toSet(), {'h-used'});
    // 本地文件：孤儿被删，被引用的保留
    expect(orphanFile.existsSync(), isFalse);
    expect(usedFile.existsSync(), isTrue);
  });

  test('decodeNote reads schema 2 with assets field', () async {
    final hash = 'a' * 64;
    final remoteJson = jsonEncode({
      'schema': 2,
      'id': 'note-with-assets',
      'title': 'T',
      'content':
          '{"insert":"hi\\n","embed":{"type":"image","source":"asset://$hash.png"}}',
      'type': 'rich_text',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'assets': [
        {'hash': hash, 'ext': 'png', 'kind': 'image'}
      ],
      'deletedAt': null,
    });
    await backend.mkcol('/notes-app/');
    await backend.mkcol('/notes-app/notes/');
    await backend.upload(
      '/notes-app/notes/note-with-assets.json',
      Uint8List.fromList(utf8.encode(remoteJson)),
    );

    await sync.syncOnce();

    final local = (await storage.loadNoteById('note-with-assets')).data;
    expect(local, isNotNull);
    expect(local!.syncStatus, SyncStatus.clean);
    // content 里的 asset:// 引用必须原样保留
    expect(local.content, contains('asset://$hash.png'));
  });

  // ============================================================
  // 任务 8：_doSync 串接附件 push/pull
  // ============================================================
  test('doSync pushes pending assets after notes', () async {
    final note = _makeNote('note-with-asset');
    final assetHash = 'a' * 64;
    note.content =
        '{"insert":{"image":"asset://$assetHash.png"}}{"insert":"\\n"}';
    await storage.saveNote(note.copyWith(syncStatus: SyncStatus.dirty));

    // 直接写一条 sync_assets 记录（绕过 AssetRepository，模拟历史数据）
    // localPath 必须落在 SyncService._getAssetsDir() 管理的目录里
    final assetsDirPath = '${storage.appDocumentsDirOverride}/sync-assets';
    final tmpAssetDir = Directory(assetsDirPath);
    if (!tmpAssetDir.existsSync()) tmpAssetDir.createSync(recursive: true);
    final assetFile = File('${tmpAssetDir.path}/$assetHash.png');
    await assetFile.writeAsBytes([1, 2, 3]);
    await storage.upsertSyncAsset(
      hash: assetHash,
      ext: 'png',
      localPath: assetFile.path,
      syncStatus: SyncStatus.dirty,
      refCount: 1,
    );

    await sync.syncOnce();

    expect(await backend.exists('/notes-app/notes/note-with-asset.json'), isTrue);
    expect(await backend.exists('/notes-app/assets/$assetHash.png'), isTrue);
  });

  test('doSync pulls missing assets after notes', () async {
    final assetHash = 'b' * 64;
    final remoteJson = jsonEncode({
      'schema': 2,
      'id': 'note-remote-with-asset',
      'title': 'T',
      'content':
          '{"insert":{"image":"asset://$assetHash.png"}}{"insert":"\\n"}',
      'type': 'rich_text',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'assets': [
        {'hash': assetHash, 'ext': 'png', 'kind': 'image'}
      ],
      'deletedAt': null,
    });

    await backend.mkcol('/notes-app/');
    await backend.mkcol('/notes-app/notes/');
    await backend.mkcol('/notes-app/assets/');
    await backend.upload(
      '/notes-app/notes/note-remote-with-asset.json',
      Uint8List.fromList(utf8.encode(remoteJson)),
    );
    await backend.upload(
      '/notes-app/assets/$assetHash.png',
      Uint8List.fromList([10, 20, 30]),
    );

    await sync.syncOnce();

    final records = (await storage.listSyncAssets()).data!;
    final r = records.where((x) => x.hash == assetHash).toList();
    expect(r, isNotEmpty);
    expect(r.first.syncStatus, SyncStatus.clean);
    expect(File(r.first.localPath).existsSync(), isTrue);
  });

  // ============================================================
  // 任务 9：pullMissingAssets 支持 hashFilter 单文件拉取
  // ============================================================
  test('pullMissingAssets with hashFilter pulls only specified hashes',
      () async {
    final hashD = 'd' * 64;
    final hashE = 'e' * 64;
    await backend.mkcol('/notes-app/');
    await backend.mkcol('/notes-app/assets/');
    await backend.upload(
      '/notes-app/assets/$hashD.png',
      Uint8List.fromList([1, 2, 3]),
    );
    await backend.upload(
      '/notes-app/assets/$hashE.png',
      Uint8List.fromList([4, 5, 6]),
    );

    await sync.pullMissingAssets(hashFilter: {hashD});

    final records = (await storage.listSyncAssets()).data!;
    final hashes = records.map((a) => a.hash).toSet();
    expect(hashes, contains(hashD));
    expect(hashes, isNot(contains(hashE)));
  });

  test('pullMissingAssets without hashFilter pulls all (backwards compat)',
      () async {
    final hashF = 'f' * 64;
    final hashA1 = 'a1' * 32; // 64 字符，全部 hex 合法
    await backend.mkcol('/notes-app/');
    await backend.mkcol('/notes-app/assets/');
    await backend.upload(
      '/notes-app/assets/$hashF.png',
      Uint8List.fromList([1, 2, 3]),
    );
    await backend.upload(
      '/notes-app/assets/$hashA1.png',
      Uint8List.fromList([4, 5, 6]),
    );

    await sync.pullMissingAssets(); // 不传 hashFilter

    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 2);
  });

  test('asset push failure does not block note sync', () async {
    final note = _makeNote('note-ok');
    final assetHash = 'c' * 64;
    note.content =
        '{"insert":{"image":"asset://$assetHash.png"}}{"insert":"\\n"}';
    await storage.saveNote(note.copyWith(syncStatus: SyncStatus.dirty));

    // sync_assets 记录指向一个不存在的文件
    await storage.upsertSyncAsset(
      hash: assetHash,
      ext: 'png',
      localPath: '/tmp/nonexistent-$assetHash.png', // 故意不存在
      syncStatus: SyncStatus.dirty,
      refCount: 1,
    );

    await sync.syncOnce(); // 不应抛

    expect(await backend.exists('/notes-app/notes/note-ok.json'), isTrue);
    // 该资源未被上传，sync_status 仍是 dirty
    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.syncStatus, SyncStatus.dirty);
  });
}

/// 包装 LocalBackend：让 listDir 返回"冻结的旧 etag"，让 pull 阶段看不到远端变化；
/// 同时让 upload 在携带 ifMatchEtag 时强制抛 ETagMismatchException，触发 push 阶段的
/// `on ETagMismatchException` 分支。
///
/// 使用场景：模拟"另一端在 pull 完成后、push 之前改了远端"——这种 race condition 在
/// 单线程的 LocalBackend 中无法稳定复现，因此通过 wrapper 模拟。
///
/// 注意：抛异常后的后续 upload（_handleConflict 内部）会绕过 ifMatchEtag 检查
/// （传 null 给 inner），因为 inner 的实际 etag 已与 wrapper 冻结的 etag 不一致，
/// 否则会再次抛 ETagMismatchException 导致 _handleConflict 失败。
class _PushConflictBackend implements SyncBackend {
  final LocalBackend _inner;
  final String frozenEtag;
  bool _hasThrown = false;
  bool pushConflictTriggered = false;

  _PushConflictBackend(this._inner, {required this.frozenEtag});

  @override
  Future<void> authenticate(Credentials creds) =>
      _inner.authenticate(creds);

  @override
  Future<void> mkcol(String path) => _inner.mkcol(path);

  @override
  Future<bool> exists(String path) => _inner.exists(path);

  @override
  Future<Uint8List> download(String path) => _inner.download(path);

  @override
  Future<void> delete(String path) => _inner.delete(path);

  @override
  Future<void> testConnection(String rootPath) =>
      _inner.testConnection(rootPath);

  @override
  Future<List<RemoteFile>> listDir(String path) async {
    final files = await _inner.listDir(path);
    // 返回冻结的 etag，让 pull 阶段认为远端没变化（不触发 pull 阶段冲突）
    return files
        .map((f) => RemoteFile(
              path: f.path,
              size: f.size,
              lastModified: f.lastModified,
              etag: frozenEtag,
            ))
        .toList();
  }

  @override
  Future<String> upload(String path, Uint8List bytes,
      {String? ifMatchEtag}) async {
    // 只在第一次携带 ifMatchEtag 的 upload 时抛异常（这是 _pushPhase 的 push 调用）
    if (!_hasThrown && ifMatchEtag != null) {
      _hasThrown = true;
      pushConflictTriggered = true;
      throw ETagMismatchException(
        path: path,
        expected: ifMatchEtag,
        actual: 'remote-changed-by-other-device',
      );
    }
    // 异常已触发后，绕过 inner 的 ifMatchEtag 检查（inner 实际 etag 与 frozenEtag 不一致）
    return _inner.upload(path, bytes);
  }
}

/// 模拟 NAS WebDAV：PROPFIND 返回的 href 是 host 绝对路径（含共享名前缀），
/// 与客户端 upload/download 用的相对 rootPath 形式不一致。
///
/// - listDir 返回的 RemoteFile.path 加上 [prefix]
/// - download/delete/exists/upload 等收到的 path 若以 [prefix] 开头则剥掉，
///   转发给 inner（inner 只认相对 rootPath 形式）
class _PrefixedPathBackend implements SyncBackend {
  final LocalBackend _inner;
  final String prefix;

  _PrefixedPathBackend(this._inner, {required this.prefix});

  String _stripPrefix(String p) =>
      p.startsWith(prefix) ? p.substring(prefix.length) : p;

  @override
  Future<void> authenticate(Credentials creds) =>
      _inner.authenticate(creds);

  @override
  Future<void> mkcol(String path) => _inner.mkcol(_stripPrefix(path));

  @override
  Future<bool> exists(String path) => _inner.exists(_stripPrefix(path));

  @override
  Future<Uint8List> download(String path) =>
      _inner.download(_stripPrefix(path));

  @override
  Future<void> delete(String path) => _inner.delete(_stripPrefix(path));

  @override
  Future<void> testConnection(String rootPath) =>
      _inner.testConnection(_stripPrefix(rootPath));

  @override
  Future<List<RemoteFile>> listDir(String path) async {
    final files = await _inner.listDir(_stripPrefix(path));
    // PROPFIND 模拟：返回的 href 加上共享名前缀（host 绝对路径形式）
    return files
        .map((f) => RemoteFile(
              path: '$prefix${f.path}',
              size: f.size,
              lastModified: f.lastModified,
              etag: f.etag,
            ))
        .toList();
  }

  @override
  Future<String> upload(String path, Uint8List bytes,
          {String? ifMatchEtag}) =>
      _inner.upload(_stripPrefix(path), bytes, ifMatchEtag: ifMatchEtag);
}
