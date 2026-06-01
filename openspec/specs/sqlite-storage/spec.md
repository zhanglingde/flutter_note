## ADDED Requirements

### Requirement: SQLite 数据库初始化
系统 SHALL 在应用启动时初始化 SQLite 数据库，创建 `notes` 表和必要的索引。数据库文件存储在应用本地目录中。

#### Scenario: 首次启动创建数据库
- **WHEN** 应用首次启动且 SQLite 数据库不存在
- **THEN** 系统创建数据库文件、`notes` 表及 `updated_at` 索引

#### Scenario: 后续启动复用数据库
- **WHEN** 应用再次启动且 SQLite 数据库已存在
- **THEN** 系统直接打开已有数据库，不重新创建表

### Requirement: SQLite CRUD 操作
系统 SHALL 通过 SQLite 实现笔记的增删改查操作，包括保存、加载、删除、搜索和排序。

#### Scenario: 保存笔记到 SQLite
- **WHEN** 调用 `saveNote(note)` 保存笔记
- **THEN** 笔记被插入或更新到 `notes` 表中

#### Scenario: 从 SQLite 加载所有笔记
- **WHEN** 调用 `loadNotes()` 加载笔记
- **THEN** 返回 `notes` 表中的所有笔记，转换为 `Note` 对象列表

#### Scenario: 按 ID 加载单条笔记
- **WHEN** 调用 `loadNoteById(id)` 加载笔记
- **THEN** 返回匹配 ID 的 `Note` 对象，不存在则返回 null

#### Scenario: 从 SQLite 删除笔记
- **WHEN** 调用 `deleteNote(id)` 删除笔记
- **THEN** 该 ID 的记录从 `notes` 表中移除

#### Scenario: 在 SQLite 中搜索笔记
- **WHEN** 调用 `searchNotes(query)` 搜索笔记
- **THEN** 返回标题或内容包含查询关键词的笔记列表

#### Scenario: 按更新时间降序加载笔记
- **WHEN** 调用 `loadNotesSortedByUpdatedAt()` 加载笔记
- **THEN** 返回按 `updated_at` 降序排列的笔记列表

### Requirement: 自动保存防抖
系统 SHALL 提供 2 秒延迟的自动保存防抖机制，避免频繁写入 SQLite。

#### Scenario: 连续编辑时防抖保存
- **WHEN** 用户连续编辑笔记，多次触发保存
- **THEN** 仅在最后一次编辑后 2 秒执行一次保存

#### Scenario: 退出时立即保存
- **WHEN** 调用 `flushAutoSave()` 强制保存
- **THEN** 立即执行待保存的笔记写入 SQLite

### Requirement: Hive 到 SQLite 数据迁移
系统 SHALL 在首次启动时自动检测并迁移 Hive 数据到 SQLite，迁移完成后记录标记。

#### Scenario: 首次启动自动迁移
- **WHEN** 应用首次使用 SQLite 启动，检测到 Hive 中有笔记数据
- **THEN** 所有 Hive 中的笔记被迁移到 SQLite，迁移完成后写入标记

#### Scenario: 已迁移的启动跳过迁移
- **WHEN** 应用启动时检测到迁移标记已存在
- **THEN** 跳过迁移流程，直接使用 SQLite 数据

#### Scenario: 迁移过程数据完整性
- **WHEN** Hive 中有 N 条笔记
- **THEN** 迁移后 SQLite 中有且仅有相同的 N 条笔记，字段内容完全一致

### Requirement: 资源清理
系统 SHALL 在应用退出时正确关闭 SQLite 数据库连接，释放资源。

#### Scenario: 关闭数据库
- **WHEN** 调用 `close()` 方法
- **THEN** 取消待执行的自动保存定时器，关闭 SQLite 数据库连接
