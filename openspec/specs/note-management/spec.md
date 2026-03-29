# 笔记管理规格

## ADDED Requirements

### Requirement: 创建新笔记
系统应当允许用户创建新笔记并选择编辑器类型。

#### Scenario: 创建富文本笔记
- **WHEN** 用户点击创建按钮并选择富文本
- **THEN** 创建新的空白富文本笔记并打开编辑器

#### Scenario: 创建 markdown 笔记
- **WHEN** 用户点击创建按钮并选择 markdown
- **THEN** 创建新的空白 markdown 笔记并打开编辑器

#### Scenario: 自动生成笔记 ID
- **WHEN** 新笔记被创建
- **THEN** 自动分配唯一标识符

### Requirement: 编辑现有笔记
系统应当允许用户编辑之前创建的笔记。

#### Scenario: 打开笔记进行编辑
- **WHEN** 用户点击列表中的笔记
- **THEN** 笔记在适当的编辑器（富文本或 markdown）中打开

#### Scenario: 保存编辑
- **WHEN** 用户修改笔记内容
- **THEN** 更改自动保存

#### Scenario: 更新时间戳
- **WHEN** 笔记被修改并保存
- **THEN** updatedAt 时间戳被更新

### Requirement: 删除笔记
系统应当允许用户在确认后删除笔记。

#### Scenario: 请求删除笔记
- **WHEN** 用户滑动笔记或点击删除按钮
- **THEN** 显示确认对话框

#### Scenario: 确认删除
- **WHEN** 用户确认删除
- **THEN** 笔记被永久移除

#### Scenario: 取消删除
- **WHEN** 用户取消删除
- **THEN** 笔记保持不变

### Requirement: 查看笔记列表
系统应当在列表视图中显示所有笔记。

#### Scenario: 显示笔记卡片
- **WHEN** 用户查看笔记列表
- **THEN** 每条笔记显示标题、预览和时间戳

#### Scenario: 按更新时间排序
- **WHEN** 笔记列表显示
- **THEN** 笔记按 updatedAt 降序排序

#### Scenario: 显示笔记类型指示器
- **WHEN** 笔记列表显示
- **THEN** 每条笔记显示类型指示器（富文本或 markdown）

### Requirement: 笔记标题处理
系统应当自动处理笔记标题。

#### Scenario: 从首行自动生成标题
- **WHEN** 用户创建没有明确标题的笔记
- **THEN** 内容首行成为标题

#### Scenario: 截断长标题
- **WHEN** 笔记首行超过 50 个字符
- **THEN** 标题在列表视图中以省略号截断

#### Scenario: 处理空笔记
- **WHEN** 笔记没有内容
- **THEN** 标题显示为"无标题"

### Requirement: 笔记预览
系统应当在列表中显示笔记内容预览。

#### Scenario: 显示文本预览
- **WHEN** 笔记列表显示
- **THEN** 显示内容的前 100 个字符作为预览

#### Scenario: 预览中移除格式
- **WHEN** 富文本笔记在列表中
- **THEN** 预览显示不带格式的纯文本

### Requirement: 搜索笔记
系统应当允许用户搜索笔记。

#### Scenario: 按标题搜索
- **WHEN** 用户输入搜索查询
- **THEN** 显示标题匹配的笔记

#### Scenario: 按内容搜索
- **WHEN** 用户输入搜索查询
- **THEN** 显示内容包含查询的笔记

#### Scenario: 清除搜索
- **WHEN** 用户清空搜索字段
- **THEN** 再次显示所有笔记

### Requirement: 跨平台一致性
系统应当在 Android、Web 和 Windows 平台上提供一致的笔记管理。

#### Scenario: Android 上创建笔记
- **WHEN** 用户在 Android 上创建笔记
- **THEN** 笔记出现在列表中并可编辑

#### Scenario: Web 上创建笔记
- **WHEN** 用户在 Web 浏览器中创建笔记
- **THEN** 笔记出现在列表中并可编辑

#### Scenario: Windows 上创建笔记
- **WHEN** 用户在 Windows 上创建笔记
- **THEN** 笔记出现在列表中并可编辑
