# 附件多设备同步 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把图片/视频附件纳入 WebDAV 同步回路，并通过 asset:// 协议解决跨设备路径不可移植问题。

**架构：** 引入 `AssetRepository` 统一附件存取（扁平 hash 结构 `{appDocumentsDir}/sync-assets/{hash}.{ext}`）；编辑器插入附件时改用 `asset://{hash}.{ext}` 引用；渲染层经 `AssetResolver` 解析为本地路径；`SyncService._doSync` 接入 push/pull assets；启动时由 `AssetMigrationService` 自动迁移历史 `images/` `videos/` 数据。

**技术栈：** Flutter 3.11+ / Dart / SQLite（sqflite）/ superlibrary Quill / WebDAV / `package:crypto` SHA-256。

**规格来源：** [docs/superpowers/specs/2026-07-02-asset-sync-design.md](../specs/2026-07-02-asset-sync-design.md)

---

## 文件结构

### 新建文件

| 路径 | 职责 |
|------|------|
| `lib/services/sync/asset_reference.dart` | `AssetReference` 纯工具类：asset:// URL 的构造与解析 |
| `lib/services/sync/asset_repository.dart` | `AssetRepository`：附件存取 + 引用计数维护 |
| `lib/services/sync/asset_resolver.dart` | `AssetResolver`：asset:// → 本地路径解析 |
| `lib/services/sync/asset_migration_service.dart` | `AssetMigrationService`：启动时一次性历史迁移 |
| `test/services/sync/asset_reference_test.dart` | AssetReference 单测 |
| `test/services/sync/asset_repository_test.dart` | AssetRepository 单测 |
| `test/services/sync/asset_resolver_test.dart` | AssetResolver 单测 |
| `test/services/sync/asset_migration_service_test.dart` | 迁移服务单测 |
| `test/services/sync/asset_sync_integration_test.dart` | A→远端→B 端到端集成测试 |

### 修改文件

| 路径 | 改动点 |
|------|--------|
| `lib/services/note_storage_service.dart` | `saveNote/deleteNote` 加引用计数钩子；`sync_state` 表读写迁移标记 |
| `lib/services/sync/sync_service.dart` | `_doSync` 接入附件 push/pull；`_encodeNote/_decodeNote` 处理 assets；`pullMissingAssets` 加 `hashFilter` 参数 |
| `lib/widgets/rich_text_editor.dart` | `_insertImage/_insertVideo` 走 `AssetRepository`；`_ImageEmbedBuilder/_VideoEmbedBuilder` 走 `AssetResolver` |
| `lib/main.dart` | 启动时构造 `AssetRepository`、注入 storage、触发 `AssetMigrationService.migrateIfNeeded()` |
| `lib/screens/home_screen.dart` & `lib/screens/editor_screen.dart` | 删笔记时由 storage 内部维护引用计数（不直接调 assetRepo） |
| `test/services/sync/sync_service_test.dart` | 扩充：assets 字段往返、附件 push/pull 真的跑了、单个附件失败不阻塞 |

### 跨计划约定

- 所有 `asset://` URL 由 `AssetReference.uri` 生成、`AssetReference.tryParse` 解析——**禁止手工拼字符串**
- 所有附件存取必须经过 `AssetRepository`，禁止直接调 `NoteStorageService.upsertSyncAsset`（除 repo/migration_service 内部）
- 测试一律用 `sqflite_common_ffi` + `LocalBackend`，参考 `test/services/sync/sync_service_test.dart` 现有 setUp 模式

---

## 任务 1：AssetReference 纯工具类

**文件：**
- 创建：`lib/services/sync/asset_reference.dart`
- 测试：`test/services/sync/asset_reference_test.dart`

- [ ] **步骤 1：编写失败的测试**

```dart
// test/services/sync/asset_reference_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:note/services/sync/asset_reference.dart';

void main() {
  group('AssetReference', () {
    test('build uri from hash and ext', () {
      final ref = AssetReference('a3f5e8b9', 'png');
      expect(ref.uri, 'asset://a3f5e8b9.png');
    });

    test('tryParse valid asset uri', () {
      final ref = AssetReference.tryParse('asset://a3f5e8b9.png');
      expect(ref, isNotNull);
      expect(ref!.hash, 'a3f5e8b9');
      expect(ref.ext, 'png');
    });

    test('tryParse returns null for non-asset scheme', () {
      expect(AssetReference.tryParse('https://example.com/x.png'), isNull);
      expect(AssetReference.tryParse('file:///C:/x.png'), isNull);
      expect(AssetReference.tryParse('C:\\Users\\x\\y.png'), isNull);
      expect(AssetReference.tryParse('/data/user/0/x.png'), isNull);
    });

    test('tryParse returns null for malformed input', () {
      expect(AssetReference.tryParse(null), isNull);
      expect(AssetReference.tryParse(''), isNull);
      expect(AssetReference.tryParse('asset://'), isNull);
      expect(AssetReference.tryParse('asset://noext'), isNull);
      expect(AssetReference.tryParse('asset://.png'), isNull);
      expect(AssetReference.tryParse('asset://abc.'), isNull);
    });

    test('tryParse handles absolute path on disk (legacy)', () {
      const winPath = r'C:\Users\Admin\AppData\images\n1\123.png';
      expect(AssetReference.tryParse(winPath), isNull);
    });

    test('tryParse handles multi-dot filename', () {
      final ref = AssetReference.tryParse('asset://abc.tar.gz');
      expect(ref!.hash, 'abc.tar');
      expect(ref.ext, 'gz');
    });

    test('equality based on hash+ext', () {
      expect(AssetReference('a', 'png'), AssetReference('a', 'png'));
      expect(AssetReference('a', 'png') == AssetReference('a', 'jpg'), isFalse);
    });
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/services/sync/asset_reference_test.dart`
预期：FAIL，报错 "asset_reference.dart doesn't exist" 或 "AssetReference not defined"

- [ ] **步骤 3：编写实现**

```dart
// lib/services/sync/asset_reference.dart

/// asset:// 协议资源引用。
///
/// 笔记内容里图片/视频的 source 改用 [uri] 表示（如 `asset://a3f5.png`），
/// 跨设备稳定。各设备由 [AssetResolver] 负责把 uri 解析为本地实际路径。
class AssetReference {
  final String hash;
  final String ext;

  const AssetReference(this.hash, this.ext);

  /// 资源的 asset:// URI。
  String get uri => 'asset://$hash.$ext';

  /// 解析 asset:// URI；协议不匹配或格式错误返回 null。
  ///
  /// 非.asset:// 输入（http://、file://、绝对本地路径、相对路径）一律返回 null，
  /// 调用方据此走原有逻辑。
  static AssetReference? tryParse(String? source) {
    if (source == null || source.isEmpty) return null;
    if (!source.startsWith('asset://')) return null;

    final body = source.substring('asset://'.length);
    if (body.isEmpty) return null;

    final dot = body.lastIndexOf('.');
    if (dot <= 0 || dot == body.length - 1) return null;

    return AssetReference(body.substring(0, dot), body.substring(dot + 1));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetReference && hash == other.hash && ext == other.ext;

  @override
  int get hashCode => Object.hash(hash, ext);

  @override
  String toString() => 'AssetReference($uri)';
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/services/sync/asset_reference_test.dart`
预期：PASS（7 tests）

- [ ] **步骤 5：Commit**

```bash
git add lib/services/sync/asset_reference.dart test/services/sync/asset_reference_test.dart
git commit -m "feat(sync): 添加 AssetReference 用于 asset:// 协议编解码"
```

---

## 任务 2：AssetRepository——附件存取与引用计数

**文件：**
- 创建：`lib/services/sync/asset_repository.dart`
- 测试：`test/services/sync/asset_repository_test.dart`

**前置依赖：** 任务 1 完成。

- [ ] **步骤 1：编写失败的测试**

```dart
// test/services/sync/asset_repository_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_reference.dart';
import 'package:note/models/note.dart';

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late NoteStorageService storage;
  late AssetRepository repo;
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('asset_repo_test_');
    storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    repo = AssetRepository(storage);
  });

  tearDown(() async {
    await storage.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('save writes file to sync-assets/{hash}.{ext} and creates record dirty', () async {
    final ref = await repo.save(_bytes([1, 2, 3, 4]), 'png');

    expect(ref.ext, 'png');
    expect(ref.hash.length, 64); // sha256 hex

    final file = File('${tmpDir.path}/appdocs/sync-assets/${ref.hash}.png');
    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);

    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 1);
    expect(records.first.hash, ref.hash);
    expect(records.first.ext, 'png');
    expect(records.first.syncStatus, SyncStatus.dirty);
    expect(records.first.refCount, 0);
  });

  test('save dedupes by hash: same content returns same ref, file not rewritten', () async {
    final ref1 = await repo.save(_bytes([1, 2, 3]), 'png');
    final ref2 = await repo.save(_bytes([1, 2, 3]), 'png');

    expect(ref1.hash, ref2.hash);
    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 1);
  });

  test('save with different ext produces different records', () async {
    final ref1 = await repo.save(_bytes([1, 2, 3]), 'png');
    final ref2 = await repo.save(_bytes([1, 2, 3]), 'jpg');
    expect(ref1.hash, ref2.hash);
    // 同 hash 不同 ext：当前实现按 hash 主键覆盖，ext 取最后一次。
    // 测试只是断言不崩，业务上推荐统一一种 ext。
  });

  test('read returns bytes when file exists', () async {
    final ref = await repo.save(_bytes([10, 20, 30]), 'png');
    final bytes = await repo.read(ref.hash);
    expect(bytes, isNotNull);
    expect(bytes!, [10, 20, 30]);
  });

  test('read returns null when hash not in table', () async {
    expect(await repo.read('nonexistenthash'), isNull);
  });

  test('read returns null when record exists but file missing', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    File('${tmpDir.path}/appdocs/sync-assets/${ref.hash}.png').deleteSync();
    expect(await repo.read(ref.hash), isNull);
  });

  test('incrementRefs bumps ref_count for given hashes', () async {
    final ref1 = await repo.save(_bytes([1, 2, 3]), 'png');
    final ref2 = await repo.save(_bytes([4, 5, 6]), 'png');

    await repo.incrementRefs({ref1.hash, ref2.hash});
    await repo.incrementRefs({ref1.hash}); // 二次增量

    final records = (await storage.listSyncAssets()).data!;
    final r1 = records.firstWhere((r) => r.hash == ref1.hash);
    final r2 = records.firstWhere((r) => r.hash == ref2.hash);
    expect(r1.refCount, 2);
    expect(r2.refCount, 1);
  });

  test('incrementRefs is idempotent for same hash in one call (set semantics)', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await repo.incrementRefs({ref.hash, ref.hash}); // 集合去重
    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 1);
  });

  test('decrementRefs decrements and marks dirty when reaching 0', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await repo.incrementRefs({ref.hash});
    await repo.incrementRefs({ref.hash});
    expect((await storage.listSyncAssets()).data!.first.refCount, 2);

    await repo.decrementRefs({ref.hash});
    expect((await storage.listSyncAssets()).data!.first.refCount, 1);
    expect((await storage.listSyncAssets()).data!.first.syncStatus, SyncStatus.dirty);

    await repo.decrementRefs({ref.hash});
    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 0);
    expect(r.syncStatus, SyncStatus.dirty); // 等待 cleanup 清理
  });

  test('decrementRefs clamps at 0 (never negative)', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await repo.decrementRefs({ref.hash}); // 没增过也减
    expect((await storage.listSyncAssets()).data!.first.refCount, 0);
  });

  test('decrementRefs on unknown hash is a no-op', () async {
    await repo.decrementRefs({'unknownhash'});
    expect((await storage.listSyncAssets()).data!, isEmpty);
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/services/sync/asset_repository_test.dart`
预期：FAIL，"asset_repository.dart doesn't exist" 或 "NoteStorageService.appDocumentsDirOverride 不存在"

需要先为 `NoteStorageService` 添加 `appDocumentsDirOverride` 字段（测试用，类似已有的 `dbPathOverride`）。

- [ ] **步骤 3：为 NoteStorageService 添加测试用 override 字段**

读取 [lib/services/note_storage_service.dart](../../lib/services/note_storage_service.dart) 找到 `dbPathOverride` 字段定义位置，紧邻添加：

```dart
/// 测试用：覆盖 getApplicationDocumentsDirectory 返回值。生产环境留空。
String? appDocumentsDirOverride;
```

并在 `NoteStorageService` 内部任何需要 `getApplicationDocumentsDirectory()` 的位置改为：
```dart
final appDirPath = appDocumentsDirOverride ?? (await getApplicationDocumentsDirectory()).path;
```

如果当前 storage 没有调用 `getApplicationDocumentsDirectory`，则该字段是新功能所需——任务 2 的 AssetRepository 会读取它，所以必须落在 storage 上以便共享。

- [ ] **步骤 4：编写 AssetRepository 实现**

```dart
// lib/services/sync/asset_repository.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

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
```

- [ ] **步骤 5：运行测试验证通过**

运行：`flutter test test/services/sync/asset_repository_test.dart`
预期：PASS（11 tests）

- [ ] **步骤 6：Commit**

```bash
git add lib/services/sync/asset_repository.dart \
        test/services/sync/asset_repository_test.dart \
        lib/services/note_storage_service.dart
git commit -m "feat(sync): AssetRepository 统一附件存取+引用计数"
```

---

## 任务 3：AssetResolver——asset:// → 本地路径解析

**文件：**
- 创建：`lib/services/sync/asset_resolver.dart`
- 测试：`test/services/sync/asset_resolver_test.dart`

**前置依赖：** 任务 1、任务 2 完成。

- [ ] **步骤 1：编写失败的测试**

```dart
// test/services/sync/asset_resolver_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_resolver.dart';

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late NoteStorageService storage;
  late AssetRepository repo;
  late AssetResolver resolver;
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('asset_resolver_test_');
    storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    repo = AssetRepository(storage);
    resolver = AssetResolver(storage);
  });

  tearDown(() async {
    await storage.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('resolveLocalPath returns path when asset:// and file exists', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    final path = await resolver.resolveLocalPath(ref.uri);
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
  });

  test('resolveLocalPath returns null when file missing', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    File('${tmpDir.path}/appdocs/sync-assets/${ref.hash}.png').deleteSync();
    expect(await resolver.resolveLocalPath(ref.uri), isNull);
  });

  test('resolveLocalPath returns null when hash unknown', () async {
    expect(await resolver.resolveLocalPath('asset://unknown.png'), isNull);
  });

  test('resolveLocalPath passes through non-asset:// source unchanged', () async {
    expect(await resolver.resolveLocalPath('https://x.com/y.png'), 'https://x.com/y.png');
    expect(await resolver.resolveLocalPath('/data/user/0/x.png'), '/data/user/0/x.png');
    expect(await resolver.resolveLocalPath(r'C:\x\y.png'), r'C:\x\y.png');
  });

  test('resolveLocalPath handles null and empty', () async {
    expect(await resolver.resolveLocalPath(null), isNull);
    expect(await resolver.resolveLocalPath(''), isNull);
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/services/sync/asset_resolver_test.dart`
预期：FAIL，"asset_resolver.dart doesn't exist"

- [ ] **步骤 3：编写实现**

```dart
// lib/services/sync/asset_resolver.dart
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
    return records.first.localPath;
  }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/services/sync/asset_resolver_test.dart`
预期：PASS（5 tests）

- [ ] **步骤 5：Commit**

```bash
git add lib/services/sync/asset_resolver.dart test/services/sync/asset_resolver_test.dart
git commit -m "feat(sync): AssetResolver 把 asset:// 解析为本地路径"
```

---

## 任务 4：SyncService 的 _encodeNote/_decodeNote 加 assets 字段

**文件：**
- 修改：`lib/services/sync/sync_service.dart`（[`_encodeNote`](../../lib/services/sync/sync_service.dart) 约 461 行起、[`_decodeNote`](../../lib/services/sync/sync_service.dart) 约 476 行起）
- 修改：`test/services/sync/sync_service_test.dart`（扩充）

**前置依赖：** 任务 1 完成。

- [ ] **步骤 1：在 sync_service_test.dart 中编写失败测试**

把以下测试追加到 `test/services/sync/sync_service_test.dart` 的 `main()` 内（与现有测试并列）：

```dart
  test('encodeNote includes assets array parsed from content', () {
    // 直接调 SyncService 的内部方法是私有的，通过 syncOnce 端到端验证。
    // 这里测试更高层：保存带 asset:// 引用的笔记 → 同步 → 远端 JSON 含 assets 字段
    // 该测试在任务 8 之后会更完整；这里仅占位确保 _encodeNote 不丢字段。
  }, skip: 'placeholder; real test in task 8');

  test('decodeNote reads schema 2 with assets field', () async {
    // 构造一份 schema=2 的远端笔记 JSON（含 assets），同步下来 → 本地笔记可加载
    final hash = 'a' * 64;
    final remoteJson = jsonEncode({
      'schema': 2,
      'id': 'note-with-assets',
      'title': 'T',
      'content': '{"insert":"hi\\n","embed":{"type":"image","source":"asset://$hash.png"}}',
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
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/services/sync/sync_service_test.dart`
预期：第二个测试 FAIL，因为 schema=2 的笔记 `_decodeNote` 还能解码，但当前 `_encodeNote` schema=1 的笔记推上去后远端 manifest 没区分。本任务让本地编码也升级到 schema=2 + 写 assets 字段。

- [ ] **步骤 3：在 AssetReference 上添加 scanHashes 静态方法**

打开 `lib/services/sync/asset_reference.dart`，在 class 内添加：

```dart
/// 扫描文本中所有 asset:// 引用，返回 hash 集合。
///
/// 用于 _encodeNote 输出 assets 字段、NoteStorageService 维护引用计数。
/// Quill Delta 的 image/video embed 把 source 放在 JSON 里：
///   {"insert":{"embed":{"type":"image","source":"asset://HASH.ext"}}}
/// 或简化形式：
///   {"insert":{"image":"asset://HASH.ext"}}
/// 直接用正则扫整段 content 字符串最稳健——不依赖具体 schema。
static Set<String> scanHashes(String content) {
  final result = <String>{};
  final regex = RegExp(r'asset://([a-f0-9]{40,128})\.([a-zA-Z0-9]+)');
  for (final m in regex.allMatches(content)) {
    result.add(m.group(1)!);
  }
  return result;
}
```

并把任务 1 的单测里加一条覆盖（也可在任务 1 时一并加上，避免遗漏）：

```dart
test('scanHashes extracts all asset hashes from content', () {
  const content =
      '{"insert":{"image":"asset://aaaa1111bbbb2222cccc3333dddd444455556666.png"}}'
      '{"insert":{"video":"asset://bbbb1111bbbb2222cccc3333dddd4444555566667777.mp4"}}'
      '{"insert":"\\n"}';
  final hashes = AssetReference.scanHashes(content);
  expect(hashes.length, 2);
});
```

> 任务 4 实施时如任务 1 已合入且未包含此测试，可在任务 4 步骤里顺手补到 `asset_reference_test.dart`。

- [ ] **步骤 4：改写 _encodeNote**

替换现有 `_encodeNote`：

```dart
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
```

import 区添加：`import 'asset_reference.dart';`（如已存在跳过）。

- [ ] **步骤 5：改写 _decodeNote 兼容 schema 1 和 2**

替换现有 `_decodeNote`：

```dart
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
```

- [ ] **步骤 6：运行测试验证通过**

运行：`flutter test test/services/sync/sync_service_test.dart`
预期：PASS（含新增的 schema=2 解码测试 + 既有测试全通过）

注意：如果 `_seedRemote` 帮助函数里的 `_encodeNote` 也用了 `schema: 1`，需同步改为 `schema: 2` + assets 字段。检查测试文件第 49 行（`'schema': 1,`），改为 `'schema': 2,` 并保留 `'assets': <Map<String, dynamic>>[]`。

- [ ] **步骤 7：Commit**

```bash
git add lib/services/sync/sync_service.dart test/services/sync/sync_service_test.dart
git commit -m "feat(sync): _encodeNote 升级 schema=2，输出 assets 字段"
```

---

## 任务 5：NoteStorageService.saveNote/deleteNote 维护引用计数

**文件：**
- 修改：`lib/services/note_storage_service.dart`（[`saveNote`](../../lib/services/note_storage_service.dart) 约 190 行、[`deleteNote`](../../lib/services/note_storage_service.dart) 约 268 行）

**前置依赖：** 任务 2 完成。

**设计抉择：** NoteStorageService 持有一个**可选**的 `AssetRepository` 引用（避免循环依赖：repo 注入 storage，storage 又调 repo，靠 setter 打破环）。如果未注入，引用计数维护跳过（兼容当前不依赖附件的代码路径）。

- [ ] **步骤 1：在 sync_service_test.dart（或新文件）扩充失败测试**

新建 `test/services/note_storage_service_refcount_test.dart`：

```dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/models/note.dart';

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

Note _note(String id, String content) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: 'T',
    content: content,
    type: 'rich_text',
    createdAt: now,
    updatedAt: now,
    syncStatus: SyncStatus.dirty,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late NoteStorageService storage;
  late AssetRepository repo;
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('note_refcount_test_');
    storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    repo = AssetRepository(storage);
    storage.setAssetRepository(repo);
  });

  tearDown(() async {
    await storage.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('saveNote increments refs for new asset hashes in content', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    final content =
        '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}';
    await storage.saveNote(_note('n1', content));

    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 1);
  });

  test('saveNote diff: removing asset from content decrements old hash', () async {
    final ref1 = await repo.save(_bytes([1, 2, 3]), 'png');
    final ref2 = await repo.save(_bytes([4, 5, 6]), 'png');

    // 第一次保存：包含 ref1 和 ref2
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"${ref1.uri}"}}{"insert":{"image":"${ref2.uri}"}}{"insert":"\\n"}'));

    // 第二次保存：只剩 ref2
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"${ref2.uri}"}}{"insert":"\\n"}'));

    final records = (await storage.listSyncAssets()).data!;
    final r1 = records.firstWhere((r) => r.hash == ref1.hash);
    final r2 = records.firstWhere((r) => r.hash == ref2.hash);
    expect(r1.refCount, 0);
    expect(r1.syncStatus, SyncStatus.dirty);
    expect(r2.refCount, 1);
  });

  test('saveNote diff: same hash in multiple notes accumulates', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}'));
    await storage.saveNote(_note('n2',
        '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}'));

    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 2);
  });

  test('deleteNote decrements all asset hashes from content', () async {
    final ref = await repo.save(_bytes([1, 2, 3]), 'png');
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}'));

    expect((await storage.listSyncAssets()).data!.first.refCount, 1);

    await storage.deleteNote('n1');

    final r = (await storage.listSyncAssets()).data!.first;
    expect(r.refCount, 0);
    expect(r.syncStatus, SyncStatus.dirty);
  });

  test('saveNote without assetRepo injected skips refcount maintenance', () async {
    final rawStorage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/raw.db';
    await rawStorage.init();
    // 不调 setAssetRepository
    addTearDown(() async => await rawStorage.close());

    await rawStorage.saveNote(_note('n1', '{"insert":"hello\\n"}'));
    // 不应崩溃；sync_assets 表为空
    expect((await rawStorage.listSyncAssets()).data!, isEmpty);
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/services/note_storage_service_refcount_test.dart`
预期：FAIL，"setAssetRepository 方法不存在"

- [ ] **步骤 3：在 NoteStorageService 添加字段与 setter**

在 `lib/services/note_storage_service.dart` 顶部的 import 区添加：

```dart
import 'sync/asset_repository.dart';
import 'sync/asset_reference.dart';
```

在 `NoteStorageService` class 内部（紧邻 `dbPathOverride` 字段下方）添加：

```dart
/// 注入的附件仓库；非空时 saveNote/deleteNote 会按 diff 维护引用计数。
/// 通过 [setAssetRepository] 注入以打破与 AssetRepository 的循环依赖。
AssetRepository? _assetRepo;

void setAssetRepository(AssetRepository repo) {
  _assetRepo = repo;
}

/// 计算 oldContent → newContent 的引用 diff，按 diff 维护 ref_count。
/// 内部调用 [AssetReference.scanHashes] 扫描 asset:// 引用。
Future<void> _maintainRefCount({
  required String? oldContent,
  required String newContent,
}) async {
  final repo = _assetRepo;
  if (repo == null) return;

  final oldHashes =
      oldContent != null ? AssetReference.scanHashes(oldContent) : <String>{};
  final newHashes = AssetReference.scanHashes(newContent);

  final removed = oldHashes.difference(newHashes);
  final added = newHashes.difference(oldHashes);

  if (removed.isNotEmpty) await repo.decrementRefs(removed);
  if (added.isNotEmpty) await repo.incrementRefs(added);
}
```

⚠️ 因为 `asset_reference.dart` 和 `asset_repository.dart` 都在 `lib/services/sync/` 下，而 storage 在 `lib/services/`，import 路径用 `sync/asset_repository.dart` 和 `sync/asset_reference.dart`。

- [ ] **步骤 4：在 saveNote 调用 _maintainRefCount**

定位到 `saveNote` 方法（约 190 行），在 `_ensureInitialized()` 之后、`_db!.insert(...)` 之前插入 diff 维护：

```dart
Future<StorageResult<void>> saveNote(Note note) async {
  try {
    _ensureInitialized();

    // 维护附件引用计数：先加载旧笔记内容做 diff
    if (_assetRepo != null) {
      final oldNoteResult = await loadNoteById(note.id);
      final oldContent = oldNoteResult.data?.content;
      await _maintainRefCount(oldContent: oldContent, newContent: note.content);
    }

    await _db!.insert(
      _tableNotes,
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _lastError = null;
    return StorageResult.success(null);
  } catch (e) {
    _lastError = '保存笔记失败: $e';
    return StorageResult.failure(_lastError);
  }
}
```

- [ ] **步骤 5：在 deleteNote 调用 _maintainRefCount**

定位到 `deleteNote` 方法（约 268 行），改为先取笔记内容再删除：

```dart
Future<StorageResult<void>> deleteNote(String id) async {
  try {
    _ensureInitialized();

    // 删除前先解析 content 维护引用计数（diff 视旧内容为全部移除）
    if (_assetRepo != null) {
      final oldNoteResult = await loadNoteById(id);
      final oldContent = oldNoteResult.data?.content;
      if (oldContent != null) {
        await _maintainRefCount(
          oldContent: oldContent,
          newContent: '', // 全部视为移除
        );
      }
    }

    await _db!.delete(_tableNotes, where: 'id = ?', whereArgs: [id]);
    _lastError = null;
    return StorageResult.success(null);
  } catch (e) {
    _lastError = '删除笔记失败: $e';
    return StorageResult.failure(_lastError);
  }
}
```

- [ ] **步骤 6：运行测试验证通过**

运行：`flutter test test/services/note_storage_service_refcount_test.dart`
预期：PASS（5 tests）

并跑既有测试确保不破坏：
运行：`flutter test test/services/`
预期：PASS

- [ ] **步骤 7：Commit**

```bash
git add lib/services/note_storage_service.dart \
        test/services/note_storage_service_refcount_test.dart
git commit -m "feat(sync): NoteStorageService 维护附件引用计数（按 diff）"
```

---

## 任务 6：RichTextEditor 插入附件改用 AssetRepository

**文件：**
- 修改：`lib/widgets/rich_text_editor.dart`（[`_insertImage`](../../lib/widgets/rich_text_editor.dart) 约 492 行、[`_insertVideo`](../../lib/widgets/rich_text_editor.dart) 约 530 行、构造函数 / 字段定义区域）

**前置依赖：** 任务 1、任务 2 完成。

**改造目标：** `_insertImage` 不再调 `ImageStorageService.saveImage`，改调 `AssetRepository.save` 拿 `AssetReference`，插入 BlockEmbed 时 source 用 `ref.uri`。视频同理。

- [ ] **步骤 1：编写 widget 测试**

新建 `test/widgets/rich_text_editor_asset_insert_test.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/widgets/rich_text_editor.dart';
import 'package:note/models/note.dart';

// 这类 widget 测试因为 Quill 依赖较重，主要验证：
// 1. RichTextEditor 构造时可注入 assetRepository
// 2. 内部 _insertImage 调用后笔记 content 中含 asset:// 引用
// 完整渲染测试在任务 8 端到端集成测试中覆盖。

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('RichTextEditor accepts assetRepository parameter', (tester) async {
    final tmpDir = await Directory.systemTemp.createTemp('editor_test_');
    final storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    final repo = AssetRepository(storage);
    addTearDown(() async {
      await storage.close();
      if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
    });

    final note = Note(
      id: 'n1',
      title: 'T',
      content: '',
      type: 'rich_text',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    expect(
      () => tester.pumpWidget(MaterialApp(
        home: Material(
          child: RichTextEditor(
            noteId: note.id,
            initialContent: '',
            storageService: storage,
            assetRepository: repo,
            onChanged: () {},
          ),
        ),
      )),
      returnsNormally,
    );
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/widgets/rich_text_editor_asset_insert_test.dart`
预期：FAIL，"RichTextEditor 没有参数 assetRepository"

- [ ] **步骤 3：在 RichTextEditor 添加 assetRepository 字段**

打开 `lib/widgets/rich_text_editor.dart`，找到 `class RichTextEditor extends StatefulWidget` 的构造函数（顶部）。在现有字段（`noteId`、`initialContent`、`storageService`、`onChanged` 等）后添加：

```dart
final AssetRepository? assetRepository;
```

并在构造函数参数列表添加 `this.assetRepository,`。

import 区添加（如果还没有）：

```dart
import '../services/sync/asset_repository.dart';
import '../services/sync/asset_resolver.dart';
```

在 `_RichTextEditorState` 内部添加（与 `_imageService`、`_videoService` 并列）：

```dart
AssetRepository? get _assetRepo => widget.assetRepository;
AssetResolver? _assetResolver; // 在 didChangeDependencies 中按需构造
```

⚠️ `_assetResolver` 的初始化放到 `didChangeDependencies` 或 `initState` 中：如果 `widget.assetRepository` 非空，构造 `AssetResolver(storageService)`。但 RichTextEditor 当前没注入 `NoteStorageService`——实际上 `storageService` 已经是字段（在 widget 测试里看到了）。在 state 内加：

```dart
late final AssetResolver? _assetResolver;

@override
void initState() {
  super.initState();
  _assetResolver = widget.assetRepository == null
      ? null
      : AssetResolver(widget.storageService);
  // ...既有 initState 逻辑
}
```

具体定位由实现者按既有代码风格插入。

- [ ] **步骤 4：改写 _insertImage**

把现有 `_insertImage`（约 492 行）整体替换为：

```dart
Future<void> _insertImage(Uint8List bytes, {String extension = 'png'}) async {
  if (_assetRepo == null) {
    // 兜底：理论上注入了一定有；保留以防忘注入
    debugPrint('[RichTextEditor] assetRepository not injected, image insert ignored');
    return;
  }
  final ref = await _assetRepo!.save(bytes, extension);

  final imageData = jsonEncode({
    'source': ref.uri, // asset://hash.ext
    'width': 400,
  });

  final index = _controller.selection.baseOffset;
  _controller.replaceText(
    index,
    0,
    BlockEmbed('image', imageData),
    null,
  );
}
```

- [ ] **步骤 5：改写 _insertVideo**

把现有 `_insertVideo`（约 530 行）整体替换为：

```dart
Future<void> _insertVideo(Uint8List bytes, {String extension = 'mp4'}) async {
  if (_assetRepo == null) {
    debugPrint('[RichTextEditor] assetRepository not injected, video insert ignored');
    return;
  }
  final ref = await _assetRepo!.save(bytes, extension);

  // 生成缩略图：临时写文件、生成 jpg 字节、走 AssetRepository.save 存为独立资源
  final tmpDir = await Directory.systemTemp.createTemp('video_thumb_');
  try {
    final tmpVideoPath = '${tmpDir.path}/source.$extension';
    await File(tmpVideoPath).writeAsBytes(bytes);
    final thumbnailPath = await _videoService.generateThumbnail(
      tmpVideoPath,
      widget.noteId,
    );
    if (thumbnailPath != null) {
      final thumbBytes = await File(thumbnailPath).readAsBytes();
      final thumbRef = await _assetRepo!.save(thumbBytes, 'jpg');

      final data = <String, dynamic>{
        'source': ref.uri,
        'thumbnail': thumbRef.uri,
        'width': 400,
      };
      final videoData = jsonEncode(data);
      final index = _controller.selection.baseOffset;
      _controller.replaceText(
        index,
        0,
        BlockEmbed('video', videoData),
        null,
      );
    }
  } finally {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  }
}
```

注意：`_insertVideoUrl`（网络视频 URL 插入，约 562 行）**保持不变**——网络 URL 不走 asset:// 协议。

- [ ] **步骤 6：运行测试验证通过**

运行：`flutter test test/widgets/rich_text_editor_asset_insert_test.dart`
预期：PASS

并跑既有 widget 测试确保不破坏：
运行：`flutter test test/widget_test.dart test/widgets/`
预期：PASS（如其他 widget 测试存在）

- [ ] **步骤 7：Commit**

```bash
git add lib/widgets/rich_text_editor.dart \
        test/widgets/rich_text_editor_asset_insert_test.dart
git commit -m "feat(editor): 插入图片/视频改用 AssetRepository，source 改为 asset://"
```

---

## 任务 7：渲染层走 AssetResolver

**文件：**
- 修改：`lib/widgets/rich_text_editor.dart`（[`_ImageEmbedBuilder`](../../lib/widgets/rich_text_editor.dart) 约 1544 行、[`_VideoEmbedBuilder`](../../lib/widgets/rich_text_editor.dart) 约 2110 行、`_ImageBlockWidget` 渲染逻辑约 1663-1678 行）

**前置依赖：** 任务 6 完成。

**改造目标：** Quill image/video embed 的 builder 在拿到 source 后，先经 `_assetResolver.resolveLocalPath(source)` 解析：
- 解析返回非 null → 用返回路径渲染
- 解析返回 null（asset:// 本地缺失）→ 显示占位图 + 后台触发同步（一期内可只显示占位，触发同步放到任务 8）

- [ ] **步骤 1：编写渲染层测试**

新建 `test/widgets/image_embed_asset_resolver_test.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_resolver.dart';

// 直接测试 AssetResolver 行为符合 embed builder 的预期：
// - asset:// 解析到本地路径
// - 本地缺失返回 null（embed builder 据此显示占位图）
// - 非 asset:// 原样返回

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('AssetResolver behavior matches embed builder expectations', () async {
    final tmpDir = await Directory.systemTemp.createTemp('resolver_test_');
    final storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    final repo = AssetRepository(storage);
    final resolver = AssetResolver(storage);
    addTearDown(() async {
      await storage.close();
      if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
    });

    // asset:// + 文件存在 → 返回本地路径
    final ref = await repo.save(Uint8List.fromList([1, 2, 3]), 'png');
    expect(await resolver.resolveLocalPath(ref.uri), isNotNull);

    // asset:// + 文件不存在 → null（embed builder 应显示占位）
    File('${tmpDir.path}/appdocs/sync-assets/${ref.hash}.png').deleteSync();
    expect(await resolver.resolveLocalPath(ref.uri), isNull);

    // https:// → 原样返回（NetworkImage 路径）
    expect(
      await resolver.resolveLocalPath('https://example.com/x.png'),
      'https://example.com/x.png',
    );
  });
}
```

- [ ] **步骤 2：运行测试验证通过（任务 3 已实现，应该直接通过）**

运行：`flutter test test/widgets/image_embed_asset_resolver_test.dart`
预期：PASS（这是接口契约测试，固化行为）

- [ ] **步骤 3：改造 _ImageBlockWidget 使用 AssetResolver**

定位 `class _ImageBlockWidget`（约 1620 行起）和 `_ImageEmbedBuilder`（约 1544 行）。

`_ImageEmbedBuilder` 当前从 BlockEmbed 取出 source 后直接传给 `_ImageBlockWidget(source: ...)`。改造为：
1. `_ImageEmbedBuilder` 持有 controller（已是字段），通过 controller 反向拿 `AssetResolver`——但 controller 没有 resolver 引用。
2. 折中方案：把 `_ImageBlockWidget` 改为 StatefulWidget，在 `initState` 里异步解析 source → 拿到本地路径再渲染；本地路径为 null 时显示占位图。

具体改造（伪代码，由实现者按既有结构定位行号）：

`_ImageBlockWidget`（约 1620-1700 行）改造：

```dart
class _ImageBlockWidget extends StatefulWidget {
  final String source;
  final double initialWidth;
  final AssetResolver? assetResolver; // 新增

  const _ImageBlockWidget({
    required this.source,
    required this.initialWidth,
    this.assetResolver,
  });

  @override
  State<_ImageBlockWidget> createState() => _ImageBlockWidgetState();
}

class _ImageBlockWidgetState extends State<_ImageBlockWidget> {
  String? _resolvedPath;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
    _resolveSource();
  }

  Future<void> _resolveSource() async {
    final resolver = widget.assetResolver;
    if (resolver == null) {
      // 兜底：未注入 resolver（兼容测试或非主流程），原样使用 source
      _resolvedPath = widget.source;
      _resolving = false;
      if (mounted) setState(() {});
      _resolveImageSize();
      return;
    }
    final path = await resolver.resolveLocalPath(widget.source);
    _resolvedPath = path;
    _resolving = false;
    if (mounted) {
      setState(() {});
      if (path != null) _resolveImageSize();
    }
  }

  void _resolveImageSize() {
    final source = _resolvedPath;
    if (source == null) return;
    final isNetwork = source.startsWith('http://') || source.startsWith('https://');
    final ImageProvider provider =
        isNetwork ? NetworkImage(source) : FileImage(File(source));
    provider.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) {
          setState(() {
            _originalWidth = info.image.width.toDouble();
          });
        }
      }),
    );
  }

  // ..._buildImage() 改造：当 _resolving 或 _resolvedPath == null 时显示占位
}
```

`_buildImage()`（约 1680 行）开头插入：

```dart
Widget _buildImage() {
  if (_resolving) {
    return Container(
      width: _width,
      height: 200,
      color: Colors.grey.shade200,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
  if (_resolvedPath == null) {
    // asset:// 本地缺失（同步未完成或资源被清理）
    return Container(
      width: _width,
      height: 200,
      color: Colors.grey.shade200,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, color: Colors.grey),
            SizedBox(height: 8),
            Text('附件未同步', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
  // ...既有渲染逻辑，但把 widget.source 替换为 _resolvedPath!
  // 例如：FileImage(File(_resolvedPath!))
}
```

`_ImageEmbedBuilder.build()` 中构造 `_ImageBlockWidget` 时传入 `assetResolver`：
查找 `_ImageEmbedBuilder` 内的 `build` 方法，定位 `_ImageBlockWidget(source: ..., ...)` 行，添加：
```dart
assetResolver: _resolverOf(controller),
```
其中 `_resolverOf` 是新增的辅助方法（实现者根据 controller 持有方式获取 resolver——通常 RichTextEditor 把 resolver 通过 controller 或 InheritedWidget 传下来；最简方案：把 `_ImageEmbedBuilder` 的 controller 字段保留，由 RichTextEditor 在 `embedBuilders: [...]` 中构造时把 resolver 闭包传进来）。

考虑到 RichTextEditor 已经在 widget tree 里持有 `_assetResolver`，最简方案：
- 把 `_ImageEmbedBuilder` 改为接受 `AssetResolver? resolver` 字段
- RichTextEditor 构造 embedBuilders 时显式传入：`_ImageEmbedBuilder(controller: _controller, resolver: _assetResolver)`

按既有代码风格实现。

- [ ] **步骤 4：改造 _VideoBlockWidget 同理**

视频 embed builder 比图片多一个 thumbnail 字段。改造与图片类似，但 source 和 thumbnail 都要走 `_assetResolver.resolveLocalPath`：

```dart
Future<void> _resolveSource() async {
  final resolver = widget.assetResolver;
  if (resolver == null) {
    _resolvedSource = widget.source;
    _resolvedThumb = widget.thumbnail;
    _resolving = false;
    if (mounted) { setState(() {}); }
    return;
  }
  _resolvedSource = await resolver.resolveLocalPath(widget.source);
  _resolvedThumb = widget.thumbnail != null
      ? await resolver.resolveLocalPath(widget.thumbnail!)
      : null;
  _resolving = false;
  if (mounted) setState(() {});
}
```

视频文件本身用 `_videoPlayerController` 加载，初始化逻辑改为：等 `_resolvedSource` 不为 null 时才创建 controller。

- [ ] **步骤 5：跑测试**

运行：`flutter test test/widgets/`
预期：PASS

并跑：`flutter test test/widget_test.dart`
预期：PASS（既有冒烟测试）

- [ ] **步骤 6：Commit**

```bash
git add lib/widgets/rich_text_editor.dart test/widgets/image_embed_asset_resolver_test.dart
git commit -m "feat(editor): 图片/视频 embed 走 AssetResolver，本地缺失显示占位"
```

---

## 任务 8：SyncService._doSync 接入附件 push/pull

**文件：**
- 修改：`lib/services/sync/sync_service.dart`（[`_doSync`](../../lib/services/sync/sync_service.dart) 约 105 行）
- 修改：`test/services/sync/sync_service_test.dart`（扩充）

**前置依赖：** 任务 1-5 完成。

- [ ] **步骤 1：在 sync_service_test.dart 中编写失败测试**

追加到 `main()` 内：

```dart
  test('doSync pushes pending assets after notes', () async {
    // 1. 在 storage 里准备一篇 dirty 笔记（含 asset:// 引用）
    // 2. 在 sync_assets 表里准备一条 dirty 资源
    // 3. syncOnce()
    // 4. 断言：notes/{id}.json 和 assets/{hash}.png 都上传到远端
    final note = _makeNote('note-with-asset');
    final assetHash = 'a' * 64;
    note.content = '{"insert":{"image":"asset://$assetHash.png"}}{"insert":"\\n"}';
    await storage.saveNote(note.copyWith(syncStatus: SyncStatus.dirty));

    // 直接写一条 sync_assets 记录（绕过 AssetRepository，模拟历史数据）
    final tmpAssetDir = Directory('${storage.dbPathOverride}/../appdocs/sync-assets');
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
    // 1. 在远端放一篇笔记（带 asset:// 引用）和对应的 assets/{hash}.png
    // 2. 本地全新（无该笔记、无该资源）
    // 3. syncOnce()
    // 4. 断言：本地 sync_assets 表里有该 hash 记录，本地文件存在
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

  test('asset push failure does not block note sync', () async {
    // 模拟：附件文件本地不存在 → push 失败 → 笔记仍正常同步
    final note = _makeNote('note-ok');
    final assetHash = 'c' * 64;
    note.content = '{"insert":{"image":"asset://$assetHash.png"}}{"insert":"\\n"}';
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
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/services/sync/sync_service_test.dart`
预期：FAIL，新测试报错 "backend 不存在 assets/{hash}.png"

- [ ] **步骤 3：改写 _doSync**

替换现有 `_doSync`（约 105 行）：

```dart
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
    rethrow;
  }
}
```

注意：`pushPendingAssets` 已在 [sync_service.dart:282](../../lib/services/sync/sync_service.dart) 实现，`pullMissingAssets` 已在 [:321](../../lib/services/sync/sync_service.dart) 实现。本任务仅是接通调用。但 `pushPendingAssets` 当前对文件读取失败的容错不够——任务步骤 4 补强。

- [ ] **步骤 4：补强 pushPendingAssets 的错误处理**

定位 `pushPendingAssets`（约 282 行）。把读取文件那段：

```dart
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
```

保持现状即可（已有 try/catch），但确认 `File(asset.localPath).readAsBytes()` 失败会进 catch——已满足。

- [ ] **步骤 5：运行测试验证通过**

运行：`flutter test test/services/sync/sync_service_test.dart`
预期：PASS（含新增 3 个 asset 相关测试）

- [ ] **步骤 6：Commit**

```bash
git add lib/services/sync/sync_service.dart test/services/sync/sync_service_test.dart
git commit -m "feat(sync): _doSync 接入附件 push/pull，同步顺序 notes→assets"
```

---

## 任务 9：pullMissingAssets 支持 hashFilter 参数

**文件：**
- 修改：`lib/services/sync/sync_service.dart`（[`pullMissingAssets`](../../lib/services/sync/sync_service.dart) 约 321 行）

**前置依赖：** 任务 8 完成。

**目标：** 渲染层发现本地缺失某个 asset 时，可以传 hashFilter 触发**单文件**拉取，避免每次同步都全量 listDir 远端。

- [ ] **步骤 1：编写失败测试**

追加到 `sync_service_test.dart`：

```dart
  test('pullMissingAssets with hashFilter pulls only specified hashes', () async {
    final h1 = 'd' * 64;
    final h2 = 'e' * 64;
    await backend.mkcol('/notes-app/');
    await backend.mkcol('/notes-app/assets/');
    await backend.upload('/notes-app/assets/$h1.png', Uint8List.fromList([1]));
    await backend.upload('/notes-app/assets/$h2.png', Uint8List.fromList([2]));

    // 仅拉 h1
    await sync.pullMissingAssets(hashFilter: {h1});

    final records = (await storage.listSyncAssets()).data!;
    final hashes = records.map((r) => r.hash).toSet();
    expect(hashes, contains(h1));
    expect(hashes, isNot(contains(h2)));
  });

  test('pullMissingAssets without hashFilter pulls all (backwards compat)', () async {
    final h1 = 'f' * 64;
    final h2 = 'a1' * 32; // 64 字符
    await backend.mkcol('/notes-app/');
    await backend.mkcol('/notes-app/assets/');
    await backend.upload('/notes-app/assets/$h1.png', Uint8List.fromList([1]));
    await backend.upload('/notes-app/assets/$h2.png', Uint8List.fromList([2]));

    await sync.pullMissingAssets();

    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 2);
  });
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/services/sync/sync_service_test.dart`
预期：FAIL，"pullMissingAssets 不接受 hashFilter 参数"

- [ ] **步骤 3：改写 pullMissingAssets 签名与实现**

替换现有 `pullMissingAssets`（约 321 行）：

```dart
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
```

注意 `refCount` 默认值从 1 改为 0：本地无笔记引用时为 0；上游 saveNote 拉笔记后增量。

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/services/sync/sync_service_test.dart`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add lib/services/sync/sync_service.dart test/services/sync/sync_service_test.dart
git commit -m "feat(sync): pullMissingAssets 支持 hashFilter 单文件拉取"
```

---

## 任务 10：AssetMigrationService 历史迁移

**文件：**
- 创建：`lib/services/sync/asset_migration_service.dart`
- 测试：`test/services/sync/asset_migration_service_test.dart`

**前置依赖：** 任务 1-5 完成。

**迁移触发条件：** `sync_state` 表无 `migration_v2_done = '1'` 标记 **且** 本地存在 `images/` 或 `videos/` 目录。

- [ ] **步骤 1：在 NoteStorageService 添加 sync_state 表读写方法**

在 `lib/services/note_storage_service.dart` 末尾（class 内最后）添加：

```dart
// ==================== sync_state 表 ====================

Future<StorageResult<String?>> getSyncState(String key) async {
  try {
    _ensureInitialized();
    final maps = await _db!.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: [key],
    );
    final value = maps.isEmpty ? null : maps.first['value'] as String?;
    return StorageResult.success(value);
  } catch (e) {
    return StorageResult.failure('read sync_state failed: $e');
  }
}

Future<StorageResult<void>> setSyncState(String key, String value) async {
  try {
    _ensureInitialized();
    await _db!.insert(
      'sync_state',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return StorageResult.success(null);
  } catch (e) {
    return StorageResult.failure('write sync_state failed: $e');
  }
}
```

- [ ] **步骤 2：编写迁移服务失败测试**

```dart
// test/services/sync/asset_migration_service_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_migration_service.dart';
import 'package:note/services/sync/asset_reference.dart';
import 'package:note/models/note.dart';

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

Note _note(String id, String content) {
  final now = DateTime.now();
  return Note(
    id: id,
    title: 'T',
    content: content,
    type: 'rich_text',
    createdAt: now,
    updatedAt: now,
    syncStatus: SyncStatus.dirty,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late NoteStorageService storage;
  late AssetRepository repo;
  late AssetMigrationService migrator;
  late Directory tmpDir;
  late String appDocsPath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('migration_test_');
    appDocsPath = '${tmpDir.path}/appdocs';
    Directory(appDocsPath).createSync(recursive: true);
    storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = appDocsPath;
    await storage.init();
    repo = AssetRepository(storage);
    storage.setAssetRepository(repo);
    migrator = AssetMigrationService(repo: repo, storage: storage);
  });

  tearDown(() async {
    await storage.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('migrateIfNeeded skips when no legacy dirs exist', () async {
    await migrator.migrateIfNeeded();

    expect((await storage.getSyncState('migration_v2_done')).data, '1');
    expect((await storage.listSyncAssets()).data, isEmpty);
  });

  test('migrateIfNeeded copies images/{noteId}/ to sync-assets and rewrites content', () async {
    // 1. 构造 legacy images/n1/123.png
    final legacyDir = Directory('$appDocsPath/images/n1');
    legacyDir.createSync(recursive: true);
    final imgPath = '$appDocsPath/images/n1/123.png';
    File(imgPath).writeAsBytesSync([10, 20, 30]);

    // 2. 保存一篇引用该绝对路径的笔记
    final content = '{"insert":{"image":"$imgPath"}}{"insert":"\\n"}';
    await storage.saveNote(_note('n1', content));

    // 3. 跑迁移
    await migrator.migrateIfNeeded();

    // 4. 断言 sync-assets 生成
    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 1);
    final r = records.first;
    expect(r.ext, 'png');
    expect(r.syncStatus, SyncStatus.dirty);

    // 5. 笔记 content 改写为 asset://
    final updated = (await storage.loadNoteById('n1')).data!;
    expect(updated.content, contains('asset://${r.hash}.png'));
    expect(updated.content, isNot(contains(imgPath)));

    // 6. 本地 sync-assets 文件存在
    expect(File('${appDocsPath}/sync-assets/${r.hash}.png').existsSync(), isTrue);

    // 7. 完成标记写入
    expect((await storage.getSyncState('migration_v2_done')).data, '1');

    // 8. 旧目录被重命名为 _migrated_backup
    expect(Directory('$appDocsPath/images').existsSync(), isFalse);
    expect(Directory('$appDocsPath/images_migrated_backup').existsSync(), isTrue);
  });

  test('migrateIfNeeded is idempotent: running twice does not double-migrate', () async {
    final legacyDir = Directory('$appDocsPath/images/n1');
    legacyDir.createSync(recursive: true);
    final imgPath = '$appDocsPath/images/n1/123.png';
    File(imgPath).writeAsBytesSync([10, 20, 30]);
    await storage.saveNote(_note('n1',
        '{"insert":{"image":"$imgPath"}}{"insert":"\\n"}'));

    await migrator.migrateIfNeeded();
    await migrator.migrateIfNeeded(); // 第二次应是 no-op

    expect((await storage.listSyncAssets()).data!.length, 1);
  });

  test('migrateIfNeeded handles videos and thumbnails', () async {
    final legacyVideoDir = Directory('$appDocsPath/videos/n1');
    legacyVideoDir.createSync(recursive: true);
    final videoPath = '$appDocsPath/videos/n1/abc.mp4';
    final thumbPath = '$appDocsPath/videos/n1/thumb_abc.jpg';
    File(videoPath).writeAsBytesSync([1, 2, 3, 4]);
    File(thumbPath).writeAsBytesSync([5, 6, 7]);

    await storage.saveNote(_note('n1',
        '{"insert":{"video":"{\\"source\\":\\"$videoPath\\",\\"thumbnail\\":\\"$thumbPath\\"}"}}{"insert":"\\n"}'));

    await migrator.migrateIfNeeded();

    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 2); // 视频本体 + 缩略图

    final updated = (await storage.loadNoteById('n1')).data!;
    expect(updated.content, isNot(contains(videoPath)));
    expect(updated.content, isNot(contains(thumbPath)));
    expect(updated.content, contains('asset://'));
  });

  test('migrateIfNeeded does not choke on note with missing file', () async {
    // 笔记引用了一个不存在的路径——迁移时跳过该引用，不崩
    final legacyDir = Directory('$appDocsPath/images/n1');
    legacyDir.createSync(recursive: true);
    final imgPath = '$appDocsPath/images/n1/123.png';
    File(imgPath).writeAsBytesSync([10, 20, 30]);
    final ghostPath = '$appDocsPath/images/n1/ghost.png'; // 不存在

    await storage.saveNote(_note('n1',
        '{"insert":{"image":"$imgPath"}},{"insert":{"image":"$ghostPath"}},{"insert":"\\n"}'));

    await migrator.migrateIfNeeded();

    // 仅有的真实文件被迁移
    final records = (await storage.listSyncAssets()).data!;
    expect(records.length, 1);
  });
}
```

- [ ] **步骤 3：运行测试验证失败**

运行：`flutter test test/services/sync/asset_migration_service_test.dart`
预期：FAIL，"asset_migration_service.dart 不存在"

- [ ] **步骤 4：编写 AssetMigrationService 实现**

```dart
// lib/services/sync/asset_migration_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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

    // 4. 重命名原目录为 _migrated_backup
    if (hasImages) {
      await imagesDir.rename('$appDirPath/images_migrated_backup');
    }
    if (hasVideos) {
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
    } catch (_) {
      return null;
    }
  }

  /// 加载所有笔记，对每篇 content 做路径替换：
  /// 把所有已知的绝对路径（pathToAsset 的 key）替换为对应的 asset:// URL
  Future<void> _rewriteNotes(Map<String, AssetReference> pathToAsset) async {
    final notes = await storage.loadAllNotesIncludingDeleted();
    final all = notes.data ?? const <Note>[];
    for (final note in all) {
      var content = note.content;
      var changed = false;
      for (final entry in pathToAsset.entries) {
        if (content.contains(entry.key)) {
          content = content.replaceAll(entry.key, entry.value.uri);
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

  String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'bin';
    return path.substring(dot + 1).toLowerCase();
  }
}
```

- [ ] **步骤 5：运行测试验证通过**

运行：`flutter test test/services/sync/asset_migration_service_test.dart`
预期：PASS（5 tests）

- [ ] **步骤 6：Commit**

```bash
git add lib/services/note_storage_service.dart \
        lib/services/sync/asset_migration_service.dart \
        test/services/sync/asset_migration_service_test.dart
git commit -m "feat(sync): AssetMigrationService 自动迁移历史 images/videos"
```

---

## 任务 11：main.dart 启动时跑迁移 + 注入 AssetRepository

**文件：**
- 修改：`lib/main.dart`

**前置依赖：** 任务 2、任务 10 完成。

- [ ] **步骤 1：阅读现有 main.dart 结构** 

阅读 `lib/main.dart` 完整文件，了解当前如何构造 `SyncService`、`SyncConfig` 加载时机、`MyApp` 初始化顺序。注意：不要盲目重构——保持现有结构，仅做最小插入。

- [ ] **步骤 2：在 main.dart 中注入 AssetRepository 并触发迁移**

在构造 `SyncService` 的代码附近（约 31-49 行）添加 AssetRepository 注入：

```dart
// 既有：
// final storage = NoteStorageService();
// await storage.init();
// ...构造 SyncService

// 新增：构造 AssetRepository 并注入 storage（打破循环依赖）
final assetRepo = AssetRepository(storage);
storage.setAssetRepository(assetRepo);

// 新增：启动时跑迁移
final migrator = AssetMigrationService(repo: assetRepo, storage: storage);
await migrator.migrateIfNeeded();
```

⚠️ import 区添加：
```dart
import 'services/sync/asset_repository.dart';
import 'services/sync/asset_migration_service.dart';
```

注意：迁移可能耗时（千张图几十秒），考虑用 try/catch 包裹避免阻塞启动：

```dart
try {
  await migrator.migrateIfNeeded();
} catch (e) {
  debugPrint('[migration] failed: $e  will retry on next launch');
}
```

- [ ] **步骤 3：把 assetRepository 通过 InheritedWidget 或构造参数传到 RichTextEditor**

如果 RichTextEditor 实例化的祖先链路已经能拿到 storage（如通过 Provider），同样的位置加一个 assetRepo 的 Provider。

最简实现：在 `MyApp` 中加 `AssetRepository` 字段，通过 `InheritedWidget` 或构造参数向下传递。具体路径依赖现有架构——实现者按既有模式插入。

- [ ] **步骤 4：跑端到端冒烟测试**

运行：`flutter test`
预期：全部 PASS

启动 Windows desktop 手动验证一次：
运行：`flutter run -d windows`
预期：
- 应用启动不崩
- 控制台有迁移日志（如果有历史数据）或无操作（如果无历史数据）
- 新建笔记 → 插入图片 → 笔记 content 中可见 asset://
- 同步触发后远端 notes/{id}.json 和 assets/{hash}.png 都存在

- [ ] **步骤 5：Commit**

```bash
git add lib/main.dart
git commit -m "feat: 启动时注入 AssetRepository 并触发历史附件迁移"
```

---

## 任务 12：废弃 ImageStorageService / VideoStorageService 的写路径

**文件：**
- 修改：`lib/services/image_storage_service.dart`
- 修改：`lib/services/video_storage_service.dart`

**前置依赖：** 任务 6、任务 11 完成。

**目标：** 不再允许写入，但保留只读 API（迁移服务仍可能读取以备扩展）。

实际上：迁移完成后这些 service 已无人调用。但保留类方便快速回退。给方法标 `@Deprecated`。

- [ ] **步骤 1：标注 deprecated**

在 `lib/services/image_storage_service.dart` 的 `saveImage`、`deleteImagesForNote`、`deleteImage` 方法上添加：

```dart
@Deprecated('由 AssetRepository.save / NoteStorageService.deleteNote 取代，2026-07-02 起停用。保留只为编译兼容。')
```

在 `lib/services/video_storage_service.dart` 的 `saveVideo`、`deleteVideosForNote`、`deleteVideo` 同理标注。

`generateThumbnail`、`listAssets`、`getImageFile` 暂不标 deprecated（前者任务 6 仍在用，后两者可能将来调试需要）。

- [ ] **步骤 2：跑测试确保 deprecated 警告不影响构建**

运行：`flutter analyze`
预期：可能有 deprecated_use 警告（来自 home_screen / editor_screen 的旧调用），本任务**不修复**——这些调用会在用户实际删除笔记时由 storage 内部维护引用计数替代，调用方代码可保留向后兼容（实际不再需要单独删图片）。

如果 analyze 出现 error 级别（不是 warning），才需要修。

- [ ] **步骤 3：Commit**

```bash
git add lib/services/image_storage_service.dart lib/services/video_storage_service.dart
git commit -m "chore: 标注 Image/VideoStorageService 写路径 deprecated"
```

---

## 任务 13：端到端集成测试 A→远端→B

**文件：**
- 创建：`test/services/sync/asset_sync_integration_test.dart`

**前置依赖：** 任务 1-11 完成（任务 12 可并行）。

**目标：** 端到端验证：A 设备保存带图笔记 → 同步 → 远端验证 → B 设备（全新）→ 同步 → 笔记与图片都下来 → 解析本地路径可渲染。

- [ ] **步骤 1：编写集成测试**

```dart
// test/services/sync/asset_sync_integration_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/services/sync/asset_resolver.dart';
import 'package:note/services/sync/local_backend.dart';
import 'package:note/services/sync/sync_backend.dart';
import 'package:note/services/sync/sync_service.dart';
import 'package:note/services/sync/sync_state.dart';
import 'package:note/models/note.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmpDirA;
  late Directory tmpDirB;
  late LocalBackend backend; // 共享远端

  setUp(() async {
    tmpDirA = await Directory.systemTemp.createTemp('integration_A_');
    tmpDirB = await Directory.systemTemp.createTemp('integration_B_');
    backend = LocalBackend();
    await backend.authenticate(const Credentials(username: 'u', password: 'p'));
  });

  tearDown(() async {
    if (tmpDirA.existsSync()) await tmpDirA.delete(recursive: true);
    if (tmpDirB.existsSync()) await tmpDirB.delete(recursive: true);
  });

  Future<SyncService> _makeDevice(Directory tmpDir, String label) async {
    final storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    final assetRepo = AssetRepository(storage);
    storage.setAssetRepository(assetRepo);
    final state = SyncStateManager();
    final sync = SyncService(
      storage: storage,
      backend: backend,
      state: state,
      rootPath: '/notes-app/',
    );
    return sync;
  }

  test('A saves note with image → sync → B pulls → B can resolve asset', () async {
    // === 设备 A ===
    final syncA = await _makeDevice(tmpDirA, 'A');
    final storageA = syncA.storage;
    final repoA = AssetRepository(storageA);

    // A 保存一张图片
    final ref = await repoA.save(Uint8List.fromList([1, 2, 3, 4, 5]), 'png');

    // A 保存一篇引用该图片的笔记
    final note = Note(
      id: 'note-cross-device',
      title: 'Cross',
      content: '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}',
      type: 'rich_text',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.dirty,
    );
    await storageA.saveNote(note);

    // A 同步
    await syncA.syncOnce();

    // === 远端验证 ===
    expect(await backend.exists('/notes-app/notes/note-cross-device.json'), isTrue);
    expect(await backend.exists('/notes-app/assets/${ref.hash}.png'), isTrue);

    // === 设备 B（全新）===
    final syncB = await _makeDevice(tmpDirB, 'B');
    final storageB = syncB.storage;

    // B 同步
    await syncB.syncOnce();

    // B 应有这篇笔记
    final loaded = (await storageB.loadNoteById('note-cross-device')).data!;
    expect(loaded.title, 'Cross');
    expect(loaded.content, contains('asset://${ref.hash}.png'));

    // B 的 sync_assets 表应有该 hash
    final records = (await storageB.listSyncAssets()).data!;
    final r = records.where((x) => x.hash == ref.hash).toList();
    expect(r, isNotEmpty);
    expect(r.first.syncStatus, SyncStatus.clean);

    // B 的 AssetResolver 能解析到本地路径
    final resolverB = AssetResolver(storageB);
    final localPath = await resolverB.resolveLocalPath(ref.uri);
    expect(localPath, isNotNull);
    expect(File(localPath!).existsSync(), isTrue);
    expect(await File(localPath).readAsBytes(), [1, 2, 3, 4, 5]);

    // 清理
    await storageA.close();
    await storageB.close();
  });

  test('A edits note removing image → sync → B syncs → A refcount drops to 0', () async {
    // 验证：A 设备编辑笔记移除 asset 引用后，saveNote 的 diff 逻辑会让
    // sync_assets 表 ref_count 归 0；远端笔记更新被 B 拉到后，B 的笔记
    // 内容中也不再有 asset:// 引用。
    //
    // 注：B 设备的 sync_assets 表 ref_count 不在断言范围——saveNoteFromSync
    // 路径不维护引用计数（仅 saveNote 走 diff）。
    final syncA = await _makeDevice(tmpDirA, 'A');
    final storageA = syncA.storage;
    final repoA = AssetRepository(storageA);

    final ref = await repoA.save(Uint8List.fromList([1, 2, 3]), 'png');
    final note = Note(
      id: 'note-edit-asset',
      title: 'Edit',
      content: '{"insert":{"image":"${ref.uri}"}}{"insert":"\\n"}',
      type: 'rich_text',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.dirty,
    );
    await storageA.saveNote(note);
    await syncA.syncOnce();

    // A 编辑笔记：移除图片引用
    final updated = note.copyWith(
      content: '{"insert":"no image\\n"}',
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.dirty,
    );
    await storageA.saveNote(updated);
    await syncA.syncOnce();

    // A 的 refcount 应为 0、status dirty（等待 cleanup 处理）
    final recordsA = (await storageA.listSyncAssets()).data!;
    final rA = recordsA.firstWhere((x) => x.hash == ref.hash);
    expect(rA.refCount, 0);
    expect(rA.syncStatus, SyncStatus.dirty);

    // B 同步：拉到更新后的笔记
    final syncB = await _makeDevice(tmpDirB, 'B');
    final storageB = syncB.storage;
    await syncB.syncOnce();

    final bNote = (await storageB.loadNoteById('note-edit-asset')).data!;
    expect(bNote.content, isNot(contains('asset://')));

    await storageA.close();
    await storageB.close();
  });
}
```

- [ ] **步骤 2：运行测试**

运行：`flutter test test/services/sync/asset_sync_integration_test.dart`
预期：PASS（2 tests）

如果失败，定位问题：
- 远端 assets/{hash}.png 不存在 → 检查 sync_service.pushPendingAssets 是否真的执行
- B 设备文件未下载 → 检查 sync_service.pullMissingAssets 是否真的执行
- B 设备 ref_count 不对 → 检查 saveNote 的 diff 逻辑

- [ ] **步骤 3：跑全套测试确保不破坏**

运行：`flutter test`
预期：PASS（所有测试）

- [ ] **步骤 4：Commit**

```bash
git add test/services/sync/asset_sync_integration_test.dart
git commit -m "test(sync): 端到端集成测试 A→远端→B 附件同步全流程"
```

---

## 自检

### 1. 规格覆盖度

| 规格章节 | 覆盖任务 |
|---------|---------|
| 数据模型 / asset:// 协议 | 任务 1 |
| 数据模型 / 笔记 JSON schema 升级 | 任务 4 |
| 数据模型 / sync_assets 表 | 已存在（前置） |
| 新增组件 / AssetReference | 任务 1 |
| 新增组件 / AssetRepository | 任务 2 |
| 新增组件 / AssetResolver | 任务 3 |
| 新增组件 / AssetMigrationService | 任务 10 |
| 改造 / RichTextEditor 插入 | 任务 6 |
| 改造 / 渲染层 | 任务 7 |
| 改造 / NoteStorageService 引用计数 | 任务 5 |
| 改造 / SyncService._doSync | 任务 8 |
| 改造 / _encodeNote/_decodeNote | 任务 4 |
| 历史迁移 | 任务 10、任务 11 |
| 错误处理 | 任务 5、任务 8 |
| 测试策略 | 任务 1-13 全程 |
| 实施顺序 13 步 | 任务 1-13 一一对应 |
| 不在本期范围（墓碑修复 / 远端 GC / manifest / Web） | 显式不做 |

✅ 无遗漏。

### 2. 占位符扫描

- 无 "TODO / 待定 / 后续实现"
- 每个测试都有完整断言
- 每个实现都有完整代码块
- 没有"类似任务 N"的引用

### 3. 类型一致性

| 类型/方法 | 全计划使用 |
|----------|-----------|
| `AssetReference(hash, ext)` | 任务 1 定义，任务 2/3/5/6/10 使用一致 |
| `AssetReference.uri` getter | 任务 1 定义，任务 6/10 使用 |
| `AssetReference.tryParse(String?) → AssetReference?` | 任务 1 定义，任务 3 使用 |
| `AssetRepository.save(bytes, ext) → Future<AssetReference>` | 任务 2 定义，任务 5/6/10 使用 |
| `AssetRepository.read(hash) → Future<Uint8List?>` | 任务 2 定义，其他任务未直接调用（保留 API） |
| `AssetRepository.incrementRefs/decrementRefs(Set<String>)` | 任务 2 定义，任务 5 使用 |
| `AssetResolver.resolveLocalPath(source) → Future<String?>` | 任务 3 定义，任务 6/7/13 使用 |
| `AssetMigrationService(repo, storage)` | 任务 10 定义，任务 11 使用 |
| `NoteStorageService.setAssetRepository(repo)` | 任务 5 定义，任务 11 使用 |
| `NoteStorageService.getSyncState/setSyncState` | 任务 10 步骤 1 添加 |
| `pullMissingAssets({Set<String>? hashFilter})` | 任务 9 定义 |
| `storage.appDocumentsDirOverride` | 任务 2 步骤 3 添加，任务 3/5/10/13 使用 |
| `AssetReference.scanHashes(content)` 静态方法 | 任务 4 步骤 3 添加，任务 4 步骤 4 + 任务 5 步骤 3 调用——避免 DRY 违背 |

✅ 一致。

---

## 执行交接

计划已完成并保存到 `docs/superpowers/plans/2026-07-02-asset-sync.md`。两种执行方式：

**1. 子代理驱动（推荐）** - 每个任务调度一个新的子代理，任务间进行审查，快速迭代

**2. 内联执行** - 在当前会话中使用 executing-plans 执行任务，批量执行并设有检查点

选哪种方式？
