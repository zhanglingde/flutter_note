# Proposal: Rich Text & Markdown Notes

## Why

用户需要一个现代化的笔记应用，能够支持富文本编辑和 Markdown 格式，以满足不同场景的笔记需求。当前 Flutter 项目是一个基础的笔记应用框架，但缺乏实际的编辑和格式化能力。添加富文本和 Markdown 支持将使应用能够满足学生、专业人士和内容创作者的日常笔记需求。

## What Changes

- **新增富文本编辑器**：实现一个功能完整的富文本编辑器，支持文本格式化（粗体、斜体、下划线、删除线）、列表、标题等
- **新增 Markdown 支持**：提供 Markdown 语法输入和实时预览功能，支持常见的 Markdown 语法元素
- **新增笔记管理**：实现笔记的创建、编辑、删除、保存和加载功能
- **新增数据持久化**：使用本地存储保存笔记内容，确保数据不丢失
- **新增编辑模式切换**：允许用户在富文本模式和 Markdown 模式之间切换

## Capabilities

### New Capabilities

- `rich-text-editing`: 富文本编辑能力，包括文本格式化、段落样式、列表等编辑功能
- `markdown-support`: Markdown 语法支持和实时预览能力
- `note-storage`: 笔记数据的本地持久化存储能力
- `note-management`: 笔记的增删改查管理能力

### Modified Capabilities

（无现有能力需要修改）

## Impact

### 代码影响
- 需要引入富文本编辑器依赖包（如 `flutter_quill` 或类似包）
- 需要引入 Markdown 解析和渲染包（如 `flutter_markdown`）
- 需要引入本地存储方案（如 `shared_preferences` 或 `hive`）
- `lib/main.dart` 需要重构以集成新的编辑器和笔记管理功能

### 依赖包
- `flutter_quill` - 富文本编辑器
- `flutter_markdown` - Markdown 渲染
- `shared_preferences` 或 `hive` - 本地存储

### 平台兼容性
- 支持 Android、Web、Windows 平台
- 需要确保所有依赖包在三个平台上都能正常工作

### 用户体验
- 提供直观的编辑界面
- 支持实时预览（Markdown 模式）
- 流畅的模式切换体验
