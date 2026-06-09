## 1. 状态管理

- [x] 1.1 在 `_RichTextEditorState` 中添加 `_isMarkdownView` 和 `_charCount` 状态变量
- [x] 1.2 在 `_controller` 的监听回调中更新 `_charCount`（使用 `document.toPlainText().length`）

## 2. 底部工具栏 UI

- [x] 2.1 创建 `_buildBottomToolbar()` 方法：Container（高度 32px，灰色背景，顶部边框）内含 Row，左侧功能菜单按钮，右侧字数统计 Text
- [x] 2.2 修改 `build()` 方法的 Column，在 Expanded 之后添加 `_buildBottomToolbar()`

## 3. Markdown 源码视图

- [x] 3.1 在 `build()` 方法中，根据 `_isMarkdownView` 状态切换 Expanded 子组件：编辑器或 Markdown 视图
- [x] 3.2 创建 `_buildMarkdownView()` 方法：使用 `deltaToMarkdown()` 转换内容，用 `SelectableText` 显示在 `SingleChildScrollView` 中
- [x] 3.3 功能菜单切换逻辑：点击"查看 Markdown 源码"设置 `_isMarkdownView = true`，点击"返回编辑"设置 `_isMarkdownView = false`
