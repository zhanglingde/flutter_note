## ADDED Requirements

### Requirement: 底部工具栏显示
编辑器 SHALL 在编辑区域下方显示一行底部工具栏。底部工具栏 SHALL 包含左侧的功能菜单按钮和右侧的字数统计。

#### Scenario: 编辑器加载时显示底部工具栏
- **WHEN** 用户打开一篇笔记进入编辑器
- **THEN** 编辑器底部显示工具栏，左侧显示功能菜单按钮，右侧显示当前字数

### Requirement: 字数统计实时更新
底部工具栏 SHALL 在右侧实时显示当前笔记的字数。字数 SHALL 为笔记纯文本内容的字符数。每次内容变更时 SHALL 自动更新字数。

#### Scenario: 用户输入内容后字数更新
- **WHEN** 用户在编辑器中输入或删除文字
- **THEN** 底部工具栏右侧的字数立即更新为新值

#### Scenario: 空笔记的字数显示
- **WHEN** 笔记内容为空
- **THEN** 字数显示为 0

### Requirement: Markdown 源码视图切换
底部工具栏的功能菜单 SHALL 提供"查看 Markdown 源码"选项。点击后 SHALL 将编辑器区域切换为只读的 Markdown 源码视图。

#### Scenario: 切换到 Markdown 源码视图
- **WHEN** 用户点击功能菜单中的"查看 Markdown 源码"
- **THEN** 编辑器区域替换为显示当前笔记的 Markdown 源码文本（只读、可选中复制）

#### Scenario: 从 Markdown 视图切回编辑器
- **WHEN** 用户在 Markdown 源码视图中点击功能菜单中的"返回编辑"
- **THEN** 视图切换回富文本编辑器，内容保持不变

### Requirement: Markdown 源码内容同步
Markdown 源码视图 SHALL 实时反映当前笔记内容。切换到源码视图时 SHALL 使用 Delta → Markdown 转换器将当前内容转换为 Markdown。

#### Scenario: 源码视图显示正确的 Markdown
- **WHEN** 笔记包含标题、粗体、列表等格式
- **THEN** 源码视图显示对应的 Markdown 语法文本
