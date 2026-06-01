## Context

当前项目使用 Hive 作为本地存储引擎：
- 单一 `Box<Note>`（名称 `'notes'`），以 `note.id`（毫秒时间戳字符串）为 key
- `Note` 继承 `HiveObject`，通过 `NoteAdapter`（`note.g.dart`）做二进制序列化
- `NoteStorageService` 封装了全部 CRUD 操作，提供 `StorageResult<T>` 统一返回
- 自动保存使用 2 秒防抖（Timer），退出时 `flushAutoSave()`
- UI 层（`HomeScreen`、`EditorScreen`）通过 `storageService` 直接调用 CRUD，不感知底层存储

支持平台：Android、Web、Windows。Hive 通过 `hive_flutter` 在 Web 上使用 IndexedDB。

## Goals / Non-Goals

**Goals:**
- 将存储后端从 Hive 替换为 SQLite，保持 `NoteStorageService` 的公开 API 不变
- 提供一次性数据迁移工具，将已有 Hive 数据自动迁移到 SQLite
- 移除 Hive 相关依赖和代码
- 保持 Android、Windows 平台支持（Web 平台 SQLite 不支持，需评估）

**Non-Goals:**
- 不新增功能（标签、分类等），仅做存储层替换
- 不修改 UI 层代码（除初始化和关闭逻辑）
- 不优化搜索性能（保持现有的内存过滤方式）

## Decisions

### 决策 1：SQLite 包选择 — 使用 `sqflite`

**选择**：使用 `sqflite`（配合 `sqflite_common_ffi` 用于 Windows 桌面）

**理由**：
- `sqflite` 是 Flutter 生态中最成熟的 SQLite 包，API 简洁
- `sqflite_common_ffi` 提供 Windows/Linux/macOS 桌面支持
- 项目数据模型简单（单表），不需要 ORM 的复杂抽象
- 学习成本低，直接写 SQL 即可

**备选方案**：
- `drift`（原 moor）：功能更强的 SQLite ORM，自动生成代码，支持复杂查询和迁移。但对于当前单表场景过于重量级，引入不必要的复杂度。
- `isar`：也是 NoSQL，不符合迁移到关系型数据库的目标。

### 决策 2：数据模型 — Note 改为纯 Dart 类

**选择**：`Note` 不再继承 `HiveObject`，移除 `@HiveType`/`@HiveField` 注解，保留 `fromJson`/`toJson` 方法。在 `NoteStorageService` 中通过 `toJson`/`fromJson` 与 SQLite 交互。

**理由**：解耦数据模型与存储引擎，Note 类不依赖任何特定数据库包。

### 决策 3：数据库 Schema

**选择**：单表 `notes`，结构与当前 Note 字段一一对应：

```sql
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL DEFAULT 'rich_text',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

时间戳存储为 INTEGER（毫秒 epoch），查询时转换回 `DateTime`。

**索引**：`updated_at` 降序索引，支持按更新时间排序的场景。

### 决策 4：Web 平台处理

**选择**：暂不支持 Web 平台的 SQLite 存储。Web 平台 SQLite 缺乏成熟方案（`sqflite` 不支持 Web），保持 Hive 仅用于 Web，或后续单独评估 `sqflite` 的 Web 支持。

**实际处理**：由于项目主要目标是 Windows 和 Android，Web 平台可以作为后续迭代。

### 决策 5：数据迁移策略

**选择**：首次启动时自动检测 Hive 数据，迁移到 SQLite 后标记完成（在 SQLite 中存储迁移标记）。迁移流程：
1. 打开 SQLite 数据库
2. 检查迁移标记，未迁移则继续
3. 打开 Hive Box，遍历所有 notes 插入 SQLite
4. 关闭 Hive Box，写入迁移标记
5. 后续启动不再读取 Hive

**理由**：自动迁移，用户无感知。迁移完成后 Hive 数据保留但不再读取。

### 决策 6：NoteStorageService API 保持不变

**选择**：`NoteStorageService` 的公开方法签名保持不变（`saveNote`、`loadNotes`、`deleteNote` 等），仅修改内部实现。

**理由**：最小化 UI 层改动，降低迁移风险。

## Risks / Trade-offs

- **[风险] Web 平台不兼容** → `sqflite` 不支持 Web。当前项目支持 Web 平台，迁移后 Web 构建将不可用。Mitigation：后续可引入条件导入或使用 `sqflite` 的 Web shim。
- **[风险] 数据迁移失败** → 迁移过程中断可能导致数据丢失。Mitigation：迁移时先备份 Hive 数据，迁移成功后再清理。迁移失败时降级到 Hive。
- **[风险] Windows 平台 sqflite_common_ffi 兼容性** → `sqflite_common_ffi` 需要 SQLite native library。Mitigation：`sqflite_common_ffi` 已内置 SQLite，无需额外安装。
- **[权衡] 直接 SQL vs ORM** → 使用原始 SQL 更灵活但缺少编译时检查。对于单表场景，复杂度可控。
