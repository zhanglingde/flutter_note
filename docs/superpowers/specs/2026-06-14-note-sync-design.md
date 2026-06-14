# 笔记多设备同步（WebDAV，可扩展后端）

## 背景

当前应用是单机本地笔记应用，无后端、无用户系统。笔记数据使用 SQLite 本地存储
（`NoteStorageService`），二进制资源（图片/视频）由 `ImageStorageService` /
`VideoStorageService` 独立管理。平台：Windows、Android、Web。

用户需要"同一份笔记在多设备之间同步"。首发后端选定**坚果云 WebDAV**
（境内可用、有免费额度、标准协议），但架构要求**保持扩展能力**——未来可换 Git、
自建后端、S3 等，只需新增一个 `SyncBackend` 实现，不动同步协调层。

## 已定决策

| 维度 | 决策 |
|------|------|
| 同步场景 | 个人多设备（单用户） |
| 后端 | 坚果云 WebDAV（首发，抽象接口预留扩展） |
| 二进制资源 | 图片、视频都同步 |
| 触发时机 | 启动后延迟 2s + 编辑后 30s 防抖 + 进入前台 + 手动按钮（无后台轮询） |
| 冲突策略 | LWW（updatedAt 时间戳新的赢）+ 自动保留冲突副本 |
| 同步粒度 | 文件级映射（每篇笔记 = 一个 JSON 文件，资源按 SHA-256 命名去重） |
| 删除传播 | 软删除（墓碑 `deletedAt`），避免"删除后被复活" |

## 整体架构

三层架构，核心是 `SyncBackend` 抽象接口——同步逻辑与具体协议解耦。

```
┌─────────────────────────────────────────────────────────┐
│  UI 层（HomeScreen 同步徽章、设置页、冲突查看页）        │
└─────────────────────────────────────────────────────────┘
                       ↓ 调用
┌─────────────────────────────────────────────────────────┐
│  SyncService（同步协调器，协议无关）                    │
│  - 触发时机管理（启动 / 防抖 / 前台 / 手动）            │
│  - 同步流程编排（Pull → Push）                          │
│  - 冲突处理（LWW + 副本）                               │
│  - 资源同步（哈希去重）                                 │
│  - 状态管理（ChangeNotifier）                           │
└─────────────────────────────────────────────────────────┘
                       ↓ 依赖
┌─────────────────────────────────────────────────────────┐
│  SyncBackend 抽象接口（核心扩展点）                     │
│  listDir / download / upload / delete / mkcol / exists  │
└─────────────────────────────────────────────────────────┘
                       ↑ 实现
       ┌───────────────┼───────────────┐
       │               │               │
┌──────────┐    ┌──────────────┐  ┌────────────┐
│ WebDAV   │    │ Git (未来)   │  │ Local      │
│ Backend  │    │ Backend      │  │ Backend    │
│ (首发)   │    │              │  │ (测试用)   │
└──────────┘    └──────────────┘  └────────────┘
```

### `SyncBackend` 接口

```dart
abstract class SyncBackend {
  Future<void> authenticate(Credentials creds);
  Future<List<RemoteFile>> listDir(String path);
  Future<Uint8List> download(String path);
  Future<String> upload(String path, Uint8List bytes, {String? ifMatchEtag});
  Future<void> delete(String path);
  Future<void> mkcol(String path);
  Future<bool> exists(String path);
}

class RemoteFile {
  final String path;
  final int size;
  final DateTime lastModified;
  final String? etag;  // WebDAV ETag，用于乐观锁
}
```

`upload` 的 `ifMatchEtag` 参数是关键——底层映射为 HTTP `If-Match` 头做乐观锁。
远程文件在我们读后被改过时 PUT 返回 412，上层据此触发冲突处理。

### 与现有代码的边界

- `NoteStorageService` 对外接口不变（仍是本地 SQLite 唯一入口），仅扩展 Note 模型字段
- `SyncService` 通过 `NoteStorageService` 读写本地数据，不直接碰 SQLite
- `ImageStorageService` / `VideoStorageService` 不变，但暴露 `listAssets()` 给 SyncService 用
- `Note` 模型扩展：新增 `remoteEtag`、`localHash`、`syncStatus`、`deletedAt`

## 远程目录结构与数据格式

### 远程目录

```
/notes-app/                          # 根目录（用户在设置里配置）
├── manifest.json                    # 全局清单（加速增量同步的缓存）
├── notes/
│   ├── <uuid>.json                  # 笔记（文件名 = 笔记 UUID）
│   ├── <uuid>__conflict-<ISO时间戳>.json   # 冲突副本
│   └── ...
└── assets/
    ├── <sha256>.png                 # 资源按内容哈希命名（去重）
    ├── <sha256>.mp4
    └── ...
```

### 笔记文件格式（`<uuid>.json`）

```json
{
  "schema": 1,
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "周会笔记",
  "content": "{\"insert\":\"...\"}",
  "type": "rich_text",
  "createdAt": "2026-06-14T10:00:00Z",
  "updatedAt": "2026-06-14T15:30:00Z",
  "assets": [
    {"hash": "3a7bd5e2...", "ext": "png"},
    {"hash": "9f2c1b8a...", "ext": "mp4"}
  ],
  "deletedAt": null
}
```

要点：

- `content` 保持现状（Quill Delta JSON 字符串）
- `assets` 是引用关系——资源独立存储，笔记只记 hash + 扩展名
- `deletedAt` 软删除（墓碑），多端删除同步必备，否则 A 设备删除后 B 设备同步时会"复活"
- `schema: 1` 版本号，未来格式演进时迁移用

### `manifest.json`（同步加速缓存）

```json
{
  "version": 1,
  "generatedAt": "2026-06-14T15:30:00Z",
  "notes": {
    "<uuid>.json": {"etag": "\"abc\"", "size": 2048, "hash": "...", "updatedAt": "..."}
  },
  "assets": {
    "<sha256>.png": {"etag": "\"def\"", "size": 102400, "refCount": 3}
  }
}
```

- 避免每次同步都 PROPFIND 整个目录
- 客户端缓存本地，远端拉取后比对 etag 决定是否下载
- **不是真源**，远端实际状态为准；manifest 损坏可以重建

## 本地 SQLite schema 改造（数据库版本 1 → 2）

```sql
ALTER TABLE notes ADD COLUMN remote_etag TEXT;
ALTER TABLE notes ADD COLUMN local_hash TEXT;
ALTER TABLE notes ADD COLUMN sync_status TEXT;     -- 'clean' | 'dirty' | 'conflict'
ALTER TABLE notes ADD COLUMN deleted_at INTEGER;

CREATE TABLE sync_assets (
  hash TEXT PRIMARY KEY,
  ext TEXT NOT NULL,
  local_path TEXT NOT NULL,
  remote_etag TEXT,
  sync_status TEXT NOT NULL,
  ref_count INTEGER DEFAULT 0
);

CREATE TABLE sync_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
-- 存：lastSyncAt、manifestHash、cursorToken 等
```

`Note.fromMap` / `Note.toMap` 同步扩展（保持旧字段不变，向后兼容）。

## 同步流程

### 整体编排：Pull → Push

```
syncOnce():
  1. 状态 = syncing
  2. authenticate(creds) → 失败则状态 = authError, return
  3. ensureRootDirs() → MKCOL /notes/ /assets/（已存在则忽略）
  4. pullPhase()      # 远程更新到本地
  5. pushPhase()      # 本地变更到远程
  6. updateManifest() # 上传新的 manifest.json
  7. 状态 = idle, lastSyncAt = now
```

### Pull 阶段（远程 → 本地）

```
pullPhase():
  remoteManifest = downloadManifest() or fetchFreshListing()
  localNotes = storage.loadAllNotesIncludingDeleted()

  for each remoteFile in remoteManifest.notes:
    localNote = localNotes[remoteFile.id]

    if localNote == null:
        # 本地没有 → 直接下载
        download and upsert, sync_status = 'clean'

    elif localNote.syncStatus == 'clean' and localNote.remoteEtag != remoteFile.etag:
        # 本地干净但远程变了 → 下载覆盖
        download and upsert, sync_status = 'clean'

    elif localNote.syncStatus == 'dirty' and remoteFile.etag != localNote.remoteEtag:
        # 本地脏且远程也变 → 冲突
        handleConflict(localNote, remoteFile)

  # 反向：本地有但远程没有的笔记
  for each localNote where not in remoteManifest.notes:
    if localNote.syncStatus == 'clean' and localNote.deletedAt == null:
        # 本地干净但远程没了 → 远程被删 → 本地也软删
        mark localNote deletedAt = now, sync_status = 'dirty'
    # dirty 的本地新笔记由 pushPhase 处理
```

### Push 阶段（本地 → 远程）

```
pushPhase():
  for each localNote where sync_status == 'dirty':
    try:
      if localNote.deletedAt != null:
          # 墓碑：上传带 deletedAt 的笔记文件
          uploadNoteFile(localNote, if_match_etag: localNote.remoteEtag)
      else:
          uploadAssets(localNote.assets)  # 先确保资源在远程（哈希去重跳过已有）
          uploadNoteFile(localNote, if_match_etag: localNote.remoteEtag)
      # 成功后 sync_status = 'clean'
    on ETagMismatch (HTTP 412):
      # race condition：pull 完成后、push 前远程被其他设备改过
      remoteFile = refetchRemoteMeta(localNote.id)
      handleConflict(localNote, remoteFile)
      # handleConflict 内部会重新上传或保留副本，最终该笔记 sync_status 落到 'clean'
    on otherError:
      # 单文件失败：跳过该笔记，sync_status 保持 dirty，下次重试
      recordFailure(localNote.id, error)
```

正常情况下 pull → push 顺序已经把冲突处理完了，412 只在极短的 race window 出现。
但必须处理，否则该笔记永远卡在 dirty。

### 冲突处理（LWW + 副本）

```
handleConflict(localNote, remoteFile):
  remoteNote = download(remoteFile)

  if localNote.updatedAt > remoteNote.updatedAt:
      # 本地新 → 保留本地，旧版本另存副本
      uploadConflictCopy(remoteNote)  # 上传 <uuid>__conflict-<ts>.json
      uploadNoteFile(localNote, if_match_etag: remoteFile.etag)
      localNote.syncStatus = 'clean'

  elif localNote.updatedAt < remoteNote.updatedAt:
      # 远程新 → 保留远程，本地版本另存副本
      saveLocalConflictCopy(localNote)
      upsertLocal(remoteNote)
      remoteNote.syncStatus = 'clean'

  else:
      # 时间戳相等（极少见）→ 默认本地赢 + 远程副本
      uploadConflictCopy(remoteNote)
      uploadNoteFile(localNote, ...)
```

冲突副本约定：

- 文件名 `<uuid>__conflict-<ISO时间戳>.json`，SyncService 在 pull 时跳过 `__conflict-` 前缀的文件
- UI 提供"查看冲突副本"入口，用户决定保留/合并/删除
- 不自动清理（怕丢数据），仅手动清理

### 资源同步

```
uploadAssets(assets):
  for each asset in assets:
    if remoteManifest.assets.containsKey(asset.hash):
        continue  # 远端已有，跳过（哈希去重）

    bytes = readLocalAsset(asset.localPath)
    remotePath = '/assets/<hash>.<ext>'
    backend.upload(remotePath, bytes)
    remoteManifest.assets[hash] = {etag, size, refCount: ...}
```

资源 GC（清理 refCount=0 的资源）：

- 不在同步流程内跑，避免拖慢同步
- 设置页提供独立的"清理未引用资源"操作
- 扫描所有笔记的 `assets` 列表，重建引用计数，删除 refCount=0 的资源

### 触发时机

| 触发点 | 延迟 | 行为 |
|--------|------|------|
| 应用启动后 | 2s | 自动 `syncOnce()`（延迟避开启动竞争） |
| 笔记编辑后 | 30s 防抖 | 每次编辑重置倒计时，最后一次编辑后 30s 触发 `syncOnce()`（沿用现有 `_autoSaveTimer` 模式） |
| 进入前台（`AppLifecycleState.resumed`） | 5s | 自动 `syncOnce()`（延迟避开应用切换瞬间的资源竞争） |
| 手动"立即同步"按钮 | 0 | 立即 `syncOnce()`（上次失败时按钮变红） |

约束：

- **不并发执行**：用 `Completer` 串行化，上一次未完成时新触发合并为"完成后立刻再跑一次"
- **离线跳过**：网络不可达静默跳过，不报错
- **手动按钮强制执行**：即使离线也尝试，便于失败诊断

## 错误处理

### 错误分类

| 错误类型 | 检测 | 处理 |
|---------|------|------|
| 网络不可达 | SocketException、超时 | 静默跳过，UI 显示"离线" |
| 认证失败 | HTTP 401 | UI 红色徽章"凭据无效"，停用自动同步 |
| 空间/限额不足 | HTTP 507 | UI 提示"网盘空间不足" |
| ETag 不匹配 | upload 返回 412 | 触发 `handleConflict`，重新拉取远程版本 |
| 单文件失败 | HTTP 4xx/5xx | 跳过该文件，记入 `failed_files`，继续其他 |
| manifest 损坏 | JSON 解析失败 | 删除本地缓存，回退到 PROPFIND 全量列表 |
| SQLite 写入失败 | DB 异常 | 回滚事务，sync_status 保持 dirty，下次重试 |
| 未知异常 | catch-all | 记日志，状态 = error，UI 显示"点此查看" |

### 三大原则

1. **永不崩溃**——任何同步异常不中断用户编辑
2. **永不丢数据**——冲突场景必须保留副本；上传失败前不修改本地 sync_status
3. **失败可重试**——dirty 状态保持，下次触发自动重试

### 事务一致性

```
applyPulledNote(remoteNote):
  await db.transaction((txn) async {
    await txn.insert('notes', remoteNote.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.update('notes',
        {'sync_status': 'clean', 'remote_etag': etag},
        where: 'id = ?', whereArgs: [remoteNote.id]);
  });
```

上传成功才更新 etag + sync_status；失败时状态保持 dirty。

## UI 反馈

### 顶部同步状态徽章（HomeScreen AppBar 右侧）

| 状态 | 显示 |
|------|------|
| idle（已同步） | "已同步 · N分钟前"（灰色勾选） |
| syncing | "同步中..."（蓝色旋转） |
| dirty（待同步） | "N 篇待同步"（橙色） |
| conflict | "N 个冲突待处理"（红色警告） |
| offline | "离线"（灰色） |
| error | "同步出错"（红色，点击查看详情） |

点击徽章 → 同步面板：上次同步时间 / 当前状态 / 立即同步按钮 / 查看冲突副本 / 查看同步日志。

### 设置页（新增"同步"分组）

- 启用/禁用同步开关
- 后端选择下拉（首发只有 WebDAV，预留扩展位）
- WebDAV URL / 用户名 / 应用密码 / 根目录
- "测试连接"按钮
- "立即同步"按钮
- "清理未引用资源"按钮
- "查看/清理冲突副本"入口

### 冲突副本查看页

- 列出所有 `__conflict-` 副本
- 每条：原笔记标题 / 冲突时间 / 本地 vs 远程 diff 摘要
- 操作：保留本地 / 保留远程 / 合并到当前 / 删除副本

## 测试策略

### 单元测试（核心逻辑，无网络）

用 `LocalBackend`（文件系统映射的 `SyncBackend` 实现）做测试后端：

```dart
class LocalBackend implements SyncBackend {
  final Map<String, Uint8List> _files = {};
  // 实现所有接口方法
}
```

重点覆盖：

- LWW + 副本的所有分支（本地新 / 远程新 / 时间戳相等）
- 墓碑机制（删除在多端传播）
- 资源去重和引用计数
- 防抖和串行化
- manifest 缓存失效回退到全量列表

### 集成测试（真实 HTTP，Mock 服务器）

用 `http_mock_adapter` 或 `MockClient` 模拟 WebDAV 响应：

- `listDir` 正确解析 PROPFIND 多状态响应
- `upload` 冲突时返回 412
- ETag 处理

### 手动 / E2E 测试（首发布前）

手动测试清单（每次发布前过一遍）：

- [ ] Windows 端新建笔记 → Android 端能拉到
- [ ] Android 端编辑 → Windows 端启动后能拉到
- [ ] 同一篇笔记在两端编辑 → 冲突副本正确生成
- [ ] 删除笔记 → 另一端也消失（墓碑机制）
- [ ] 图片/视频正确同步并显示
- [ ] 离线编辑 → 联网后自动同步
- [ ] 凭据错误时 UI 正确提示
- [ ] 坚果云免费额度耗尽时 UI 提示

### 测试覆盖率目标

- `SyncService` 90%+
- `ConflictResolver` 95%+（分支多）
- `WebDAVBackend` 70%+（依赖网络，重点测协议解析）
- `ManifestCache` 85%+

## 实现顺序（TDD 推进）

1. `SyncBackend` 抽象 + `LocalBackend` 实现（测试用）
2. `Note` 模型扩展 + SQLite migration（v1 → v2）
3. `ManifestCache` + 资源管理（`sync_assets` 表）
4. `ConflictResolver`（LWW + 副本）—— 重点单测
5. `SyncService`（编排 pull/push，墓碑）—— 重点单测
6. `WebDAVBackend`（用 MockClient 测协议）
7. UI：同步状态徽章 + 设置页 + 冲突查看页
8. 集成调试（手动测试清单过一遍）

## 配置项（`shared_preferences`）

```
sync.enabled         : bool
sync.backend_type    : 'webdav'        # 预留扩展
sync.webdav_url      : 'https://dav.jianguoyun.com/dav/'
sync.webdav_username : '...'
sync.webdav_password : '...'           # 坚果云应用密码
sync.webdav_root_path: '/notes-app/'
sync.last_sync_at    : ISO 时间戳
```

### 凭据安全

首发用 `shared_preferences` 存储 + TODO 注释标记后续迁移到 `flutter_secure_storage`。
坚果云"应用密码"权限受限（仅 WebDAV），泄露风险可控。

## 影响范围

新增文件：

```
lib/services/sync/
  sync_service.dart           # SyncService 协调器
  sync_backend.dart           # 抽象接口 + RemoteFile
  sync_state.dart             # 同步状态枚举 + ChangeNotifier
  conflict_resolver.dart      # LWW + 副本逻辑
  manifest_cache.dart         # 远程目录列表缓存
  webdav/
    webdav_backend.dart       # WebDAV 实现
    webdav_client.dart        # 底层 HTTP（复用现有 http 包）
  local/
    local_backend.dart        # 测试用，文件系统映射
```

修改文件：

- `lib/models/note.dart`：新增 `remoteEtag` / `localHash` / `syncStatus` / `deletedAt` 字段及 `fromMap` / `toMap` 扩展
- `lib/services/note_storage_service.dart`：
  - 数据库版本 1 → 2，添加 migration
  - 新增 `loadAllNotesIncludingDeleted()` 等查询方法
- `lib/services/image_storage_service.dart` / `lib/services/video_storage_service.dart`：暴露 `listAssets()`
- `lib/screens/home_screen.dart`：AppBar 加同步状态徽章
- `lib/main.dart`：初始化 `SyncService`，注册生命周期回调
- `pubspec.yaml`：新增依赖（`uuid` 用于笔记 ID，`crypto` 用于 SHA-256，`webdav_client` 或自写客户端）

无破坏性变更：

- `NoteStorageService` 对外接口保持向后兼容
- 数据库 v1 → v2 自动迁移
- 现有笔记数据不影响（新增字段使用默认值）
