## Why

编辑器底部缺少状态信息和快速切换视图的能力。用户需要查看当前笔记字数来掌握内容篇幅，同时需要一种方式快速预览笔记的 Markdown 源码而不离开编辑器。

## What Changes

- 在富文本编辑器最下方新增一行底部工具栏
- 底部工具栏最右边实时显示当前笔记的字数统计
- 底部工具栏左边放置功能菜单按钮，支持切换到 Markdown 源码只读视图
- Markdown 源码视图为只读模式，用户可以查看和复制内容，但不能编辑
- 编辑模式下需要切换回富文本编辑器

## Capabilities

### New Capabilities
- `editor-bottom-toolbar`: 编辑器底部工具栏，包含字数统计和 Markdown 源码视图切换功能

### Modified Capabilities
- `rich-text-editing`: 编辑器组件需要集成底部工具栏和视图模式切换

## Impact

- `lib/widgets/rich_text_editor.dart`: 主要变更文件，需添加底部工具栏 UI、字数统计逻辑、视图模式切换状态管理
- `lib/utils/delta_to_markdown.dart`: 复用现有的 Delta → Markdown 转换器用于源码视图展示
