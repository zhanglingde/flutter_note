# 笔记管理规格

## ADDED Requirements

### Requirement: 创建笔记
系统 SHALL 在用户点击新建按钮后直接创建富文本类型的笔记并打开编辑器。

#### Scenario: 点击新建按钮直接创建富文本笔记
- **WHEN** 用户点击新建笔记按钮
- **THEN** 系统直接创建一个新的富文本笔记（type = 'rich_text'，content = '[]'）
- **AND** 打开编辑器进入编辑状态
- **AND** 不显示笔记类型选择对话框

#### Scenario: 自动生成笔记 ID
- **WHEN** 新笔记被创建
- **THEN** 自动分配唯一标识符

### Requirement: 编辑现有笔记
系统应当允许用户编辑之前创建的笔记。在桌面端，点击笔记将打开新标签页或切换到已有标签页。

#### Scenario: 打开笔记进行编辑
- **WHEN** 用户点击列表中的笔记
- **THEN** 笔记在富文本编辑器中打开

#### Scenario: 桌面端打开新标签页
- **WHEN** 用户在桌面端（宽度 > 768px）点击列表中未打开的笔记
- **THEN** 系统为新笔记创建标签页并切换到该标签页
- **AND** 编辑区域显示对应笔记的编辑器

#### Scenario: 桌面端切换到已有标签页
- **WHEN** 用户在桌面端点击列表中已打开的笔记
- **THEN** 系统切换到对应的已有标签页
- **AND** 不创建新的标签页

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
