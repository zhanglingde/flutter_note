# 笔记存储规格

## ADDED Requirements

### Requirement: 本地持久化
系统应当自动将所有笔记持久化到本地存储。

#### Scenario: 内容变化时自动保存
- **WHEN** 用户停止输入 2 秒后
- **THEN** 笔记内容自动保存到本地存储

#### Scenario: 关闭笔记时保存
- **WHEN** 用户离开编辑器
- **THEN** 笔记在离开前被保存

### Requirement: 笔记检索
系统应当允许检索之前保存的笔记。

#### Scenario: 应用启动时加载笔记
- **WHEN** 用户打开应用
- **THEN** 所有之前保存的笔记被加载并显示在列表中

#### Scenario: 加载笔记进行编辑
- **WHEN** 用户点击列表中的笔记
- **THEN** 笔记内容加载到编辑器中

### Requirement: 数据格式
系统应当以结构化格式存储笔记。

#### Scenario: 存储富文本笔记
- **WHEN** 用户保存富文本笔记
- **THEN** 内容以 Quill Delta JSON 格式存储

#### Scenario: 存储 markdown 笔记
- **WHEN** 用户保存 markdown 笔记
- **THEN** 内容以纯文本存储

#### Scenario: 存储笔记元数据
- **WHEN** 笔记被保存
- **THEN** id、title、type、createdAt、updatedAt 与内容一起存储

### Requirement: 存储性能
系统应当提供快速的读写操作。

#### Scenario: 快速笔记加载
- **WHEN** 用户打开笔记列表
- **THEN** 最多 100 条笔记在 500ms 内加载

#### Scenario: 快速保存操作
- **WHEN** 笔记自动保存
- **THEN** 保存操作在 200ms 内完成

### Requirement: 数据完整性
系统应当在存储操作期间确保数据完整性。

#### Scenario: 处理存储失败
- **WHEN** 存储操作失败
- **THEN** 通知用户并提供重试选项

#### Scenario: 应用崩溃时保留数据
- **WHEN** 应用在编辑期间崩溃
- **THEN** 最后自动保存的内容被保留

### Requirement: 笔记删除
系统应当支持永久删除笔记。

#### Scenario: 删除笔记
- **WHEN** 用户确认删除笔记
- **THEN** 笔记从存储中移除

#### Scenario: 已删除笔记不在列表中
- **WHEN** 笔记被删除
- **THEN** 笔记不再出现在笔记列表中

### Requirement: 跨平台存储
系统应当在 Android、Web 和 Windows 平台上提供一致的存储行为。

#### Scenario: Android 上存储工作正常
- **WHEN** 用户在 Android 上保存笔记
- **THEN** 笔记在应用重启后持久保存

#### Scenario: Web 上存储工作正常
- **WHEN** 用户在 Web 浏览器中保存笔记
- **THEN** 笔记使用 IndexedDB 持久保存

#### Scenario: Windows 上存储工作正常
- **WHEN** 用户在 Windows 上保存笔记
- **THEN** 笔记在应用重启后持久保存

### Requirement: 存储容量处理
系统应当优雅地处理存储限制。

#### Scenario: 大笔记存储
- **WHEN** 用户创建超过 10,000 字符的笔记
- **THEN** 笔记成功保存

#### Scenario: 多笔记处理
- **WHEN** 用户有 100+ 条笔记
- **THEN** 应用性能保持可接受
