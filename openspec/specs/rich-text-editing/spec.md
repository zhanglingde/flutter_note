# 富文本编辑规格

## ADDED Requirements

### Requirement: 基本文本格式化
系统应当提供基本文本格式化能力，包括粗体、斜体、下划线和删除线。

#### Scenario: 应用粗体格式
- **WHEN** 用户选中文本并点击粗体按钮或使用 Markdown 语法 `**文本**`
- **THEN** 选中文本变为粗体

#### Scenario: 应用斜体格式
- **WHEN** 用户选中文本并点击斜体按钮或使用 Markdown 语法 `*文本*`
- **THEN** 选中文本变为斜体

#### Scenario: 应用下划线格式
- **WHEN** 用户选中文本并点击下划线按钮
- **THEN** 选中文本变为下划线

#### Scenario: 应用删除线格式
- **WHEN** 用户选中文本并点击删除线按钮或使用 Markdown 语法 `~~文本~~`
- **THEN** 选中文本变为删除线

#### Scenario: 应用行内代码格式
- **WHEN** 用户选中文本并点击代码按钮或使用 Markdown 语法 `` `代码` ``
- **THEN** 选中文本变为代码样式（等宽字体）

### Requirement: 文本对齐
系统应当支持文本对齐选项，包括左对齐、居中、右对齐和两端对齐。

#### Scenario: 更改为居中对齐
- **WHEN** 用户点击居中对齐按钮
- **THEN** 当前段落居中对齐

#### Scenario: 更改为右对齐
- **WHEN** 用户点击右对齐按钮
- **THEN** 当前段落右对齐

### Requirement: 标题支持
系统应当支持多级标题（H1、H2、H3）。

#### Scenario: 应用 H1 标题
- **WHEN** 用户选中文本并从标题下拉菜单选择 H1 或使用 Markdown 语法 `# `
- **THEN** 文本变为 H1 标题，使用适当的字体大小

#### Scenario: 应用 H2 标题
- **WHEN** 用户选中文本并从标题下拉菜单选择 H2 或使用 Markdown 语法 `## `
- **THEN** 文本变为 H2 标题，使用适当的字体大小

#### Scenario: 应用 H3 标题
- **WHEN** 用户选中文本并从标题下拉菜单选择 H3 或使用 Markdown 语法 `### `
- **THEN** 文本变为 H3 标题，使用适当的字体大小

### Requirement: 列表支持
系统应当支持有序列表和无序列表。

#### Scenario: 创建无序列表
- **WHEN** 用户点击项目符号列表按钮或使用 Markdown 语法 `- ` / `* `
- **THEN** 在光标位置创建新的无序列表项

#### Scenario: 创建有序列表
- **WHEN** 用户点击编号列表按钮或使用 Markdown 语法 `1. `
- **THEN** 在光标位置创建新的有序列表项

#### Scenario: 回车继续列表
- **WHEN** 用户在列表项中按 Enter 键
- **THEN** 创建新的列表项

#### Scenario: 创建引用块
- **WHEN** 用户点击引用按钮或使用 Markdown 语法 `> `
- **THEN** 在光标位置创建引用块

### Requirement: 工具栏可见性
系统应当在编辑器上方显示格式化工具栏，并在编辑器下方显示底部工具栏。底部工具栏 SHALL 包含功能菜单按钮和字数统计。

#### Scenario: 聚焦时显示工具栏
- **WHEN** 富文本编辑器获得焦点
- **THEN** 顶部格式化工具栏和底部工具栏均可见且可访问

#### Scenario: 工具栏按钮反映当前格式
- **WHEN** 光标位于粗体文本上
- **THEN** 粗体按钮显示激活状态

#### Scenario: 显示格式化按钮
- **WHEN** 富文本编辑器加载完成
- **THEN** 工具栏右侧显示中英文格式化按钮

#### Scenario: 点击格式化按钮
- **WHEN** 用户点击格式化按钮
- **THEN** 系统对当前文档执行中英文混排空格格式化

#### Scenario: 底部工具栏显示字数
- **WHEN** 富文本编辑器加载完成
- **THEN** 底部工具栏右侧显示当前笔记字数

#### Scenario: 底部工具栏字数实时更新
- **WHEN** 用户编辑笔记内容
- **THEN** 底部工具栏字数自动更新

### Requirement: 撤销和重做
系统应当支持撤销和重做操作。

#### Scenario: 撤销最后操作
- **WHEN** 用户点击撤销按钮或按 Ctrl+Z
- **THEN** 最后的格式化更改被还原

#### Scenario: 重做已撤销操作
- **WHEN** 用户点击重做按钮或按 Ctrl+Y
- **THEN** 之前撤销的操作被重新应用

### Requirement: 跨平台一致性
系统应当在 Android、Web 和 Windows 平台上提供一致的富文本编辑体验。

#### Scenario: Android 上格式化工作正常
- **WHEN** 用户在 Android 设备上格式化文本
- **THEN** 格式化正确应用并持久保存

#### Scenario: Web 上格式化工作正常
- **WHEN** 用户在 Web 浏览器中格式化文本
- **THEN** 格式化正确应用并持久保存

#### Scenario: Windows 上格式化工作正常
- **WHEN** 用户在 Windows 桌面上格式化文本
- **THEN** 格式化正确应用并持久保存

### Requirement: Markdown 自动转换工具栏控制

系统 SHALL 在富文本编辑器工具栏提供 Markdown 自动转换开关。

#### Scenario: 显示开关按钮
- **WHEN** 富文本编辑器加载完成
- **THEN** 工具栏显示 Markdown 转换开关按钮
- **AND** 按钮显示当前启用/禁用状态

#### Scenario: 切换开关状态
- **WHEN** 用户点击 Markdown 转换开关按钮
- **THEN** 系统切换转换功能的启用/禁用状态
- **AND** 按钮图标/颜色反映新状态

### Requirement: 工具栏大纲按钮
系统 SHALL 在富文本编辑器工具栏提供大纲面板开关按钮。

#### Scenario: 显示大纲按钮
- **WHEN** 富文本编辑器加载完成
- **THEN** 工具栏显示大纲面板开关按钮

#### Scenario: 点击大纲按钮
- **WHEN** 用户点击大纲按钮
- **THEN** 切换右侧大纲面板的显示/隐藏状态
- **AND** 按钮图标反映当前大纲面板的开启/关闭状态

### Requirement: 编辑区右侧面板支持
系统 SHALL 支持在编辑区右侧显示辅助面板（如大纲面板）。

#### Scenario: 面板展开时编辑区自适应
- **WHEN** 右侧面板展开
- **THEN** 编辑区宽度自适应缩小
- **AND** 编辑内容正常显示和编辑

#### Scenario: 面板收起时编辑区恢复
- **WHEN** 右侧面板收起
- **THEN** 编辑区恢复全宽显示
