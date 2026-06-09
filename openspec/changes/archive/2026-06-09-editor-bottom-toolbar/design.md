## Context

RichTextEditor 当前布局为 Column：顶部工具栏（48px）+ Expanded 编辑区。没有底部状态栏，没有视图切换机制，没有字数统计展示。

笔记内容以 Quill Delta JSON 存储。项目已有 `delta_to_markdown.dart` 可将 Delta 转为 Markdown 文本。

## Goals / Non-Goals

**Goals:**
- 在编辑器底部新增工具栏，显示字数统计
- 提供菜单入口切换到 Markdown 源码只读视图
- 保持与现有顶部工具栏一致的视觉风格

**Non-Goals:**
- 不做 Markdown 源码编辑（仅只读预览）
- 不做字数统计的详细分析（字符数、段落数等，仅总字数）
- 不做导出为 .md 文件功能

## Decisions

### 1. 视图模式通过状态变量管理

新增 `_isMarkdownView` bool 状态，控制 Column 中 Expanded 子组件在 QuillEditor 和 Markdown 只读视图之间切换。

**理由**：简单直接，与现有 `_showOutline` 的模式一致。不需要引入复杂的状态管理方案。

### 2. Markdown 视图使用 SelectableText + SingleChildScrollView

用 `SelectableText` 显示转换后的 Markdown 文本，包在 `SingleChildScrollView` 中支持滚动。

**理由**：满足只读+可复制的需求，无需引入额外的 Markdown 渲染组件。用户需要看到的是"源码"而非渲染结果。

**备选方案**：使用 `flutter_markdown` 渲染 Markdown — 但这与"查看源码"的需求不符，且增加依赖。

### 3. 字数统计监听 Controller 变化

在 `_controller` 的监听回调中更新字数，使用 `document.toPlainText().length`。

**理由**：实时更新，性能可接受（Delta 变更频率不高）。

### 4. 底部工具栏放在 Column 的 Expanded 之后

布局结构变为：顶部工具栏 → Expanded(编辑器或MD视图) → 底部工具栏。

**理由**：底部工具栏始终可见，不随编辑区滚动。

## Risks / Trade-offs

- [性能] 每次 Controller 变更都调用 `toPlainText()` → 仅统计纯文本长度，开销极小
- [UX] 切换视图时滚动位置不保留 → 可接受，源码视图和编辑视图的滚动位置独立
