## Why

代码块的语言选择（如 Dart、Python 等）修改后无法持久化，重新打开文档会丢失语言设置。此外，语言标识和复制按钮位于编辑器工具栏区域，与代码块在视觉上分离，用户体验不佳——用户期望这些操作控件紧贴在代码块上方。

## What Changes

- 将代码块语言选择持久化到文档数据中，确保重新打开后语言设置不丢失
- 移除工具栏区域中的代码块专属工具条（`_buildCodeBlockToolbar`）
- 在每个代码块上方新增紧贴的 header 区域，包含语言标识标签和复制图标
- 语言标签点击可切换语言，复制图标点击可复制代码内容

## Capabilities

### New Capabilities
- `code-block-header`: 代码块头部区域组件，包含语言标识和复制按钮，紧贴代码块上方显示

### Modified Capabilities

## Impact

- `lib/widgets/rich_text_editor.dart` — 主要修改文件，涉及代码块工具条移除、header widget 新增、语言持久化修复
- `lib/utils/markdown_auto_converter.dart` — 可能需要调整代码块创建时的语言回调
- 依赖 `highlight` 包的语法高亮功能不受影响
