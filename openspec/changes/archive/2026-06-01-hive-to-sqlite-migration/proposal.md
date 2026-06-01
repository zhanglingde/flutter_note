## Why

Hive 是一个基于内存的键值存储，缺乏结构化查询能力（如排序、分页、复杂条件过滤），且在数据量增长后全量加载到内存的性能开销显著。迁移到 SQLite 可以获得关系型数据库的结构化查询、索引支持和更好的扩展性，为未来的搜索优化、标签系统、分类等功能提供基础。

## What Changes

- **BREAKING** 将数据存储后端从 Hive 替换为 SQLite（使用 `sqflite` 或 `drift` 包）
- 移除 `hive`、`hive_flutter` 依赖及 `NoteAdapter`（`note.g.dart`）
- `Note` 模型不再继承 `HiveObject`，改为纯 Dart 类
- `NoteStorageService` 内部实现改为 SQLite 操作，保持外部 API 不变
- 提供数据迁移工具，将已有 Hive 数据一次性迁移到 SQLite
- 更新 `main.dart` 初始化流程

## Capabilities

### New Capabilities
- `sqlite-storage`: 基于 SQLite 的笔记存储实现，包含数据库初始化、CRUD 操作、自动保存防抖、数据迁移

### Modified Capabilities
- `note-storage`: 存储后端从 Hive 变更为 SQLite，外部行为（CRUD API、自动保存、防抖）保持不变

## Impact

- `lib/models/note.dart` — 移除 HiveObject 继承和 Hive 注解，保留 JSON 序列化
- `lib/models/note.g.dart` — 删除（不再需要 Hive TypeAdapter）
- `lib/services/note_storage_service.dart` — 重写为 SQLite 实现
- `lib/main.dart` — 更新初始化流程（SQLite 初始化替代 Hive 初始化）
- `lib/screens/home_screen.dart` — 可能需要适配初始化和关闭逻辑
- `lib/screens/editor_screen.dart` — 可能需要适配关闭逻辑
- `pubspec.yaml` — 移除 hive/hive_flutter，添加 SQLite 依赖
- 数据迁移：首次启动时自动检测 Hive 数据并迁移到 SQLite
