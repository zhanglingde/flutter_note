# 附件多设备同步（asset:// 协议 + 扁平 hash 存储）

## 背景

[`SyncService`](../../lib/services/sync/sync_service.dart) 已落地笔记文本同步（见
[`2026-06-14-note-sync-design.md`](./2026-06-14-note-sync-design.md)），但**附件（图片、视频、
缩略图）完全没有进入同步回路**。具体表现：

- [`_doSync()`](../../lib/services/sync/sync_service.dart) 只调 `_ensureRootDirs → _pullPhase
  → _pushPhase → _updateManifest`，从未调用 `pushPendingAssets()` / `pullMissingAssets()`
- [`_encodeNote()`](../../lib/services/sync/sync_service.dart) 把 `assets` 字段硬编码为空数组
- `sync_assets` 表 schema、`pushPendingAssets/pullMissingAssets` 方法骨架、远端 `assets/` 目录
  均已就位，但**生产代码从未写入这张表，骨架方法从未被触发**
- 笔记内容里图片/视频的 `source` 是**绝对本地路径**（如
  `C:\Users\Administrator\AppData\Roaming\...\images\noteId\xxx.png`），即使附件文件本身同步
  过去，B 设备也读不到——路径天然跨设备不可移植

本期目标：把附件纳入同步回路，并解决路径可移植性。

## 已定决策

| 维度 | 决策 |
|------|------|
| 路径方案 | **完整版 asset:// 协议**——笔记内容存 `asset://{hash}.{ext}`，渲染时各设备自行解析为本地路径 |
| 本地存储 | **扁平 hash 结构**——`{appDocumentsDir}/sync-assets/{hash}.{ext}`，与设计文档和 `sync_assets` 表 schema 一致 |
| 历史迁移 | **启动时自动迁移**——检测旧 `images/` `videos/` 目录，扫描算 hash、拷贝、改写笔记内容、原地保留备份 |
| 视频缩略图 | **同样走 hash 同步**——与图片/视频一视同仁，B 设备打开笔记即可见 |
| 资源 GC | **引用计数 + 仅本地 GC**——`ref_count=0` 时仅删 `sync_assets` 表记录与本地文件，远端文件保留 |
| 同步顺序 | 笔记先来（含 assets 清单） → 笔记 push → 附件 push → 附件 pull。避免 B 设备收到引用不存在资源的笔记 |
| 错误隔离 | 单个附件失败不阻塞整体同步（沿用 `_pushPhase` 已有 try/catch 模式） |

## 整体架构

```
┌────────────────────────────────────────────────────────────────┐
│  UI 层                                                          │
│  RichTextEditor._insertImage/_insertVideo                       │
│  Quill image/video embed builder（渲染层）                       │
└────────────────────────────────────────────────────────────────┘
                       ↓ 调用
┌────────────────────────────────────────────────────────────────┐
│  AssetRepository（统一附件存取入口）                            │
│  - save(bytes, ext) → 算 hash → 写文件 → upsert sync_assets     │
│  - read(hash) → 读字节                                          │
│  - incrementRefs / decrementRefs（维护引用计数）                 │
└────────────────────────────────────────────────────────────────┘
                       ↓ 依赖
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│ AssetReference   │   │ AssetResolver    │   │ NoteStorageSvc   │
│ asset:// 编解码  │   │ URL → 本地路径   │   │ save/delete 时   │
│ （纯函数）        │   │ （查 sync_assets │   │ 维护引用计数      │
│                  │   │   表）            │   │                  │
└──────────────────┘   └──────────────────┘   └──────────────────┘

┌────────────────────────────────────────────────────────────────┐
│  SyncService._doSync（接入附件同步）                            │
│  pull notes → push notes → push assets → pull assets            │
└────────────────────────────────────────────────────────────────┘
                       ↓ 依赖
┌────────────────────────────────────────────────────────────────┐
│  AssetMigrationService（一次性历史迁移，启动时触发）            │
│  images/{noteId}/ + videos/{noteId}/ → sync-assets/{hash}.{ext} │
│  + 改写笔记 content 中绝对路径 → asset://                       │
└────────────────────────────────────────────────────────────────┘
```

## 数据模型

### asset:// 协议格式

```
asset://{sha256hex}.{ext}

例: asset://a3f5e8b9c1d2e4f6a3f5e8b9c1d2e4f6a3f5e8b9c1d2e4f6a3f5e8b9c1d2e4f6.png
```

- 跨设备稳定：内容里只存哈希，本地路径各设备各自解析
- 协议头 `asset://` 与 `http://` / `file://` / `data:` 一致区分，渲染层据此分流
- 非 `asset://` 协议（如旧版的绝对路径、网络 URL）走原有逻辑

### 笔记 JSON schema 升级

旧（schema 1）：
```json
{
  "schema": 1,
  "id": "...",
  "content": "...",
  "assets": []  // 硬编码空数组
}
```

新（schema 2）：
```json
{
  "schema": 2,
  ...原有字段...,
  "assets": [
    {"hash":"a3f5...","ext":"png","kind":"image"},
    {"hash":"7c8d...","ext":"jpg","kind":"thumbnail"},
    {"hash":"1b2c...","ext":"mp4","kind":"video"}
  ]
}
```

- `schema: 1` 的远端笔记视为待迁移笔记，本地解码后走迁移流程
- `_decodeNote` 读出 `assets` 字段后用于：① 维护引用计数；② 渲染层预热拉取

### sync_assets 表（已有 schema，本期不改）

```sql
CREATE TABLE sync_assets (
  hash TEXT PRIMARY KEY,
  ext TEXT NOT NULL,
  local_path TEXT NOT NULL,
  remote_etag TEXT,
  sync_status TEXT NOT NULL DEFAULT 'clean',  -- clean / dirty
  ref_count INTEGER NOT NULL DEFAULT 0
)
```

## 新增组件

### `AssetReference`（[lib/services/sync/asset_reference.dart](../../lib/services/sync/asset_reference.dart)）

纯函数工具类，asset:// URL 的编解码。

```dart
class AssetReference {
  final String hash;
  final String ext;
  const AssetReference(this.hash, this.ext);

  static String build(String hash, String ext) => 'asset://$hash.$ext';
  static AssetReference? parse(String? source);  // 协议不匹配返回 null
  String toUri() => build(hash, ext);
}
```

### `AssetRepository`（[lib/services/sync/asset_repository.dart](../../lib/services/sync/asset_repository.dart)）

统一的附件存取入口，替代散落的 `ImageStorageService` / `VideoStorageService`。

```dart
class AssetRepository {
  AssetRepository(this._storage);  // NoteStorageService 注入

  /// 保存字节流为附件。同一哈希已存在则不重写文件、不增加 ref_count。
  /// sync_status 标 dirty（让同步推到远端）。
  Future<AssetReference> save(Uint8List bytes, String ext);

  /// 读字节流。本地文件不存在返回 null。
  Future<Uint8List?> read(String hash);

  /// 批量引用计数 +1（saveNote 时调用，传入笔记内容里所有 asset:// 引用）。
  Future<void> incrementRefs(Set<String> hashes);

  /// 批量引用计数 -1（deleteNote 时调用）。
  /// ref_count 减到 0 时 sync_status 标 dirty，留给 cleanupOrphanAssets 清理本地表与文件。
  Future<void> decrementRefs(Set<String> hashes);
}
```

### `AssetResolver`（[lib/services/sync/asset_resolver.dart](../../lib/services/sync/asset_resolver.dart)）

渲染层入口，把 asset:// 解析为本地路径。

```dart
class AssetResolver {
  AssetResolver(this._storage, this._syncService);

  /// 解析 asset:// URL 为本地绝对路径。
  /// - 协议非 asset:// → 原样返回（兼容旧 file:// 或网络 URL）
  /// - 解析后查 sync_assets 表，文件存在返回 localPath
  /// - 本地缺失返回 null，调用方应显示占位图并触发后台拉取
  Future<String?> resolveLocalPath(String source);

  /// 解析失败时由调用方主动触发同步该 hash（避免每次全量 listDir）。
  /// 调用方拿到回调后异步触发 SyncService.pullMissingAssets(hashFilter)。
}
```

### `AssetMigrationService`（[lib/services/sync/asset_migration_service.dart](../../lib/services/sync/asset_migration_service.dart)）

一次性历史迁移。启动时调用 `migrateIfNeeded()`，幂等。

```dart
class AssetMigrationService {
  AssetMigrationService(this._repo, this._storage);

  /// 检测 + 迁移。若 sync_state 表标记 migration_v2_done=1 直接返回。
  Future<void> migrateIfNeeded();
}
```

详细逻辑见下方"历史迁移"章节。

## 改造现有代码

### `RichTextEditor._insertImage` / `_insertVideo`

当前 `_insertImage`（[rich_text_editor.dart:492](../../lib/widgets/rich_text_editor.dart#L492)）：
```dart
final filePath = await _imageService.saveImage(bytes, widget.noteId, extension: extension);
final imageData = jsonEncode({'source': filePath, 'width': 400});  // 绝对路径
```

改造后：
```dart
final ref = await _assetRepo.save(bytes, extension);
final imageData = jsonEncode({'source': ref.toUri(), 'width': 400});  // asset:// URL
```

视频同理，`source` 和 `thumbnail` 都改为 `asset://`。

### 渲染层（Quill image/video embed builder）

当前 source 直接当文件路径用。改造：
1. `AssetResolver.resolveLocalPath(source)`
2. 拿到本地路径 → 渲染
3. 拿不到（返回 null）→ 显示占位图 + 异步触发 `SyncService.pullMissingAssets(hashFilter: [hash])`
4. 同步完成后 `notifyListeners()` 触发重渲

### `NoteStorageService.saveNote` / `deleteNote`

引用计数必须按 **diff** 维护，否则同一笔记多次保存会让 `ref_count` 爆炸：

- `saveNote`：
  1. 加载旧笔记（若有）→ 解析旧 content 的所有 `asset://` 引用 → `oldHashes`
  2. 解析新 content 的所有 `asset://` 引用 → `newHashes`
  3. `decrementRefs(oldHashes - newHashes)`（消失的引用）
  4. `incrementRefs(newHashes - oldHashes)`（新增的引用）
- `deleteNote`：解析当前 content → `decrementRefs(allHashes)`

注意 `incrementRefs` / `decrementRefs` 必须是**集合操作**（同一 hash 多次出现算一次），
内部 upsert 时按 hash 主键加锁或使用事务。

⚠️ **当前 `deleteNote` 是硬删除（直接 DELETE 数据库记录）**，与同步系统的"墓碑"机制不兼容。
这是独立 bug，**本期不修**，仅在引用计数维护时小心处理（删除前先解析 content 拿到引用集）。

### `SyncService._doSync`

```dart
Future<void> _doSync() async {
  state.markSyncing();
  try {
    await _ensureRootDirs();
    await _pullPhase();          // 笔记先来（带 assets 清单）
    await _pushPhase();          // 推笔记
    await pushPendingAssets();   // 推 dirty 附件
    await pullMissingAssets();   // 拉本地缺失附件
    await _updateManifest();
    state.markSuccess();
  } catch (e) { ... }
}
```

### `_encodeNote` / `_decodeNote`

- `_encodeNote`：解析 `note.content` 中所有 `asset://` 引用 → 输出 `assets` 数组；schema 升为 2
- `_decodeNote`：读 schema；schema=1 时按旧版处理（兼容远端历史笔记），不强制报错

## 历史迁移

### 触发条件

启动时检查 `sync_state` 表：
- `migration_v2_done != '1'`
- **且**本地 `images/` 或 `videos/` 目录存在

任一不满足则跳过。

### 迁移步骤（任一失败立即停止，下次重试）

1. **扫描** `images/{noteId}/*` 和 `videos/{noteId}/*`，对每个文件：
   - 算 SHA-256（用 `SyncService.sha256Hex` 已有方法）
   - **拷贝**（非移动）到 `sync-assets/{hash}.{ext}` —— 保留原文件作为安全网
   - `upsert sync_assets (sync_status='dirty', ref_count=0)`

2. **改写笔记**：加载所有笔记，解析 content 中的绝对路径 source/thumbnail：
   - 读原文件算 hash
   - 改写 source 为 `asset://{hash}.{ext}`
   - `incrementRefs(hash)` —— 至此 sync_assets.ref_count 反映真实引用
   - 笔记标 `sync_status=dirty`，schema 升为 2

3. **保留备份**：把 `images/`、`videos/` 重命名为 `images_migrated_backup/`、
   `videos_migrated_backup/`（不直接删，给用户一个后悔窗口；用户可手动清理）

4. **写完成标记**：`sync_state` 写 `migration_v2_done = '1'`

### 错误恢复

- 任一文件失败 → 立即停止 → 不写完成标记 → 下次启动重试
- 拷贝而非移动保证中途失败不丢数据
- 已改写的笔记内容**不回滚**（笔记内容改写是幂等的，重跑时 hash 一致）

### 性能预估

1000 张图 + 100 个视频 ≈ 几秒到几十秒。启动可能略卡，考虑在 main.dart 加 loading UI 提示
（"正在升级附件存储..."）。本期可不做，仅 debugPrint 进度。

## 错误处理

- 单个附件 push/pull 失败：`debugPrint`，不阻塞整体同步（沿用现有 `_pushPhase` 模式）
- 渲染时本地路径缺失：显示占位图 + 后台触发 `pullMissingAssets(hashFilter)`，避免 UI 卡死
- 迁移失败：立即停止，不写完成标记，下次重试

## 测试策略

### 单元测试

| 文件 | 覆盖点 |
|------|--------|
| `test/services/sync/asset_reference_test.dart` | build/parse 各种边界（非法 hash、缺失 ext、非 asset://、大小写敏感） |
| `test/services/sync/asset_repository_test.dart` | save 去重、read 命中/未命中、incrementRefs/decrementRefs 增减、ref_count=0 标 dirty |
| `test/services/sync/asset_resolver_test.dart` | 解析 asset:// → 查表 → 返回本地路径；非 asset:// 原样返回；本地缺失返回 null |
| `test/services/sync/asset_migration_service_test.dart` | 用临时目录构造 `images/{noteId}/` 旧数据 → 跑迁移 → 断言拷贝、改写、计数、完成标记都正确 |
| `test/services/sync/sync_service_test.dart`（扩充） | mock backend 验证 `_doSync` 调用顺序；附件 push/pull 真的跑了；单个附件失败不阻塞 |
| `test/services/note_storage_service_test.dart`（扩充） | `_encodeNote/_decodeNote` schema=2 往返；assets 字段不丢；schema=1 旧版仍能解码 |

### 集成测试

- **A 设备**：保存带图笔记 → `syncOnce()` → mock 远端验证 `notes/{id}.json` 和 `assets/{hash}.png` 都上传
- **B 设备（全新）**：`syncOnce()` → 笔记和图片都下来 → 笔记里图片能解析到本地路径
- **迁移**：构造 `images/{noteId}/` 旧数据 → 启动迁移 → 验证 `sync-assets/` 生成 + 笔记内容改写 + 完成标记

## 实施顺序

按依赖顺序，13 个步骤。每步完成后跑相关单测再进入下一步：

1. `AssetReference`（工具类 + 单测）
2. `AssetRepository`（含与 sync_assets 表交互 + 单测）
3. `AssetResolver`（含与 sync_assets 表查询 + 单测）
4. `_encodeNote` / `_decodeNote` 加 assets 字段（含 schema 升级 + 单测）
5. 改造 `RichTextEditor._insertImage` / `_insertVideo` 走 `AssetRepository`
6. 改造渲染层（Quill image/video embed builder）走 `AssetResolver`
7. `NoteStorageService.saveNote` / `deleteNote` 维护引用计数
8. `SyncService._doSync` 接入 `pushPendingAssets` / `pullMissingAssets`
9. `pullMissingAssets` 支持单 hash 拉取（`hashFilter` 参数）
10. `AssetMigrationService` 实现 + 单测
11. `main.dart` 启动时跑迁移
12. 把 `ImageStorageService` / `VideoStorageService` 标记 deprecated（保留只读供迁移用）
13. 端到端集成测试

## 不在本期范围内的事

- **墓碑机制的删除流程修复**：当前 `deleteNote` 硬删除，与同步系统的墓碑设计不兼容——
  这是独立 bug，本期只在引用计数维护时绕开
- **远端 assets 文件 GC**：保守策略不主动删除远端文件，避免误删其他设备引用中的资源；
  未来可基于 manifest 全网扫描 + 超时机制实现
- **manifest.json 真正使用**：当前实现仍是每次 `listDir` 重建，本期不动
- **Web 平台的本地路径适配**：Flutter Web 没有 `getApplicationDocumentsDirectory`，
  需要单独设计（IndexedDB 或 OPFS）；本期同步功能在 Web 上可能不可用，沿用现状
