## Why

项目决定只保留富文本编辑器，移除独立的 Markdown 编辑器。Markdown 编辑器功能与富文本编辑器重叠，且富文本编辑器已支持 Markdown 语法自动转换，独立的 Markdown 编辑模式不再必要。

## What Changes

- 删除 `lib/widgets/markdown_editor.dart` 文件
- 移除 `NoteType` 枚举，笔记类型固定为富文本
- 新建笔记时跳过类型选择，直接创建富文本笔记
- `home_screen.dart` 和 `editor_screen.dart` 移除 Markdown 编辑器导入和条件渲染
- 移除 `pubspec.yaml` 中的 `flutter_markdown` 和 `markdown` 依赖

## Capabilities

### New Capabilities
（无）

### Modified Capabilities
- `note-management`: 移除笔记类型选择，新建笔记固定为富文本
- `markdown-support`: 移除独立的 Markdown 编辑器和预览功能

## Impact

- **删除文件**: `lib/widgets/markdown_editor.dart`
- **修改文件**: `note.dart`（移除 NoteType 枚举）、`home_screen.dart`（移除 Markdown 导入/渲染/类型选择）、`editor_screen.dart`（移除 Markdown 导入/渲染/标题提取）
- **依赖变更**: 移除 `flutter_markdown`、`markdown` 两个包
- **保留**: `markdown_auto_converter.dart`（富文本编辑器内部的 Markdown 语法转换功能不受影响）
