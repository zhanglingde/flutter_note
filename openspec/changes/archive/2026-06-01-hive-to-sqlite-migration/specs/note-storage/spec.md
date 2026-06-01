## MODIFIED Requirements

### Requirement: 本地持久化
系统应当自动将所有笔记持久化到 SQLite 本地存储。

#### Scenario: 内容变化时自动保存
- **WHEN** 用户停止输入 2 秒后
- **THEN** 笔记内容自动保存到 SQLite 数据库

#### Scenario: 关闭笔记时保存
- **WHEN** 用户离开编辑器
- **THEN** 笔记在离开前保存到 SQLite 数据库

### Requirement: 数据格式
系统应当以结构化格式在 SQLite 中存储笔记。

#### Scenario: 存储富文本笔记
- **WHEN** 用户保存富文本笔记
- **THEN** 内容以 Quill Delta JSON 格式存储在 SQLite 的 `content` 字段中

#### Scenario: 存储 markdown 笔记
- **WHEN** 用户保存 markdown 笔记
- **THEN** 内容以纯文本存储在 SQLite 的 `content` 字段中

#### Scenario: 存储笔记元数据
- **WHEN** 笔记被保存
- **THEN** id、title、type、createdAt（INTEGER epoch）、updatedAt（INTEGER epoch）与内容一起存储在 `notes` 表中

### Requirement: 跨平台存储
系统应当在 Android 和 Windows 平台上提供一致的基于 SQLite 的存储行为。

#### Scenario: Android 上存储工作正常
- **WHEN** 用户在 Android 上保存笔记
- **THEN** 笔记通过 `sqflite` 存储到 SQLite 数据库，应用重启后持久保存

#### Scenario: Windows 上存储工作正常
- **WHEN** 用户在 Windows 上保存笔记
- **THEN** 笔记通过 `sqflite_common_ffi` 存储到 SQLite 数据库，应用重启后持久保存

## REMOVED Requirements

### Requirement: Web 存储支持（原跨平台存储中的 Web 场景）
**Reason**: SQLite 不支持 Web 平台，Web 存储场景暂时移除
**Migration**: 后续可引入条件导入或 Web 平台 shim 恢复 Web 支持
