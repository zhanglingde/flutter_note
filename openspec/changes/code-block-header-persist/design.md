## Context

当前富文本编辑器（`rich_text_editor.dart`）中，代码块的语法标识和复制按钮放在编辑器工具栏下方的 `_buildCodeBlockToolbar()` 中，仅在光标位于代码块内时显示。这导致：

1. 控件与代码块视觉分离——工具栏和代码块之间可能隔着大量内容
2. 用户无法直观看到每个代码块的语言（除非光标点进去）
3. 语言持久化已有 `code-block-lang` delta 属性机制，但加载时 `_loadCodeBlockLanguages()` 仅在初始化时调用一次，后续编辑导致偏移变化后映射可能失效

当前架构布局：
```
Column
  ├── _buildToolbar()          (height: 48, 固定)
  ├── _buildCodeBlockToolbar() (height: 36, 条件显示)
  └── Expanded(QuillEditor)
```

## Goals / Non-Goals

**Goals:**
- 将语言标识和复制按钮从工具栏区域移至代码块正上方，紧贴代码块显示
- 每个代码块都有自己独立的 header（不需要光标在内才显示）
- 修复语言持久化问题，确保文档重新打开后语言信息正确恢复

**Non-Goals:**
- 不修改代码块内的语法高亮逻辑
- 不修改 Quill 编辑器核心或 delta 数据模型
- 不添加新的语言支持（使用现有 `_langOptions` 列表）

## Decisions

### 决策 1：代码块 header 使用 `customLeadingBlockBuilder` 方案

**选择**：扩展现有 `_buildLeadingBlock` 回调，在代码块第一行之前渲染一个 header 容器。

**理由**：Quill 的 `customLeadingBlockBuilder` 已经为代码块提供了每行前导区域的渲染钩子。当前只用于第一行的语言 pill，可以扩展为在第一行上方插入一个完整的 header 区域。这避免了侵入 Quill 编辑器内部渲染逻辑。

**备选方案**：使用 `embedBuilders` 将代码块转为自定义 embed——过于侵入性，会破坏现有的代码块编辑体验（光标定位、选择等）。

### 决策 2：header 布局方案

**选择**：header 作为代码块背景的一部分，位于代码块矩形的顶部区域。包含左侧语言标签（可点击弹出选择器）和右侧复制按钮。

视觉设计：
```
┌─────────────────────────────────────┐
│ DART ▼                      [📋]   │  ← header（深色背景条）
├─────────────────────────────────────┤
│ void main() {                       │  ← 代码内容
│   print('Hello');                   │
│ }                                   │
└─────────────────────────────────────┘
```

### 决策 3：持久化修复策略

**选择**：保持 `code-block-lang` delta 属性方案不变，修复 `_loadCodeBlockLanguages()` 中的恢复逻辑。

当前问题分析：持久化机制本身是正确的（通过 `compose` 写入 delta），但需要在文档变更时保持 `_codeBlockLanguages` 映射与实际偏移同步。

修复方向：
- 在 `_loadCodeBlockLanguages()` 中增加更多回退查找路径
- 确保 `_detectCodeBlockCursor()` 在更新偏移时也同步更新映射

### 决策 4：移除代码块工具栏

**选择**：完全移除 `_buildCodeBlockToolbar()`，将其中的语言选择和复制功能迁移到代码块 header。

**理由**：header 方案让每个代码块始终可见其语言和操作按钮，不再依赖光标位置。减少了工具栏区域的视觉噪音。

## Risks / Trade-offs

- **[风险] `customLeadingBlockBuilder` 的布局限制** → leading 区域通常用于行号等窄元素，在第一行上方插入完整 header 可能受 Quill 布局约束。如遇限制，回退方案是使用 `Stack` + `Overlay` 在编辑器层上浮动渲染 header。
- **[风险] 性能** → 每个代码块都有 header 意味着更多 widget，对于包含大量代码块的文档可能有性能影响 → 通过 `RepaintBoundary` 和 `const` widget 优化。
- **[权衡] 语言 pill 与 header 合并** → 移除第一行的 language pill（`_buildLeadingBlock` 中的小标签），统一由 header 显示。
