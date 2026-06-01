## 1. 删除 Markdown 编辑器文件

- [x] 1.1 删除 `lib/widgets/markdown_editor.dart`

## 2. 简化 Note 数据模型

- [x] 2.1 移除 `NoteType` 枚举和 `noteType` getter，`_createNote` 参数改为无类型选择

## 3. 修改 home_screen.dart

- [x] 3.1 移除 `markdown_editor.dart` 的 import
- [x] 3.2 简化 `_showCreateDialog`：去掉 BottomSheet，FAB 直接调用 `_createNote`
- [x] 3.3 简化 `_createNote` 方法：移除 `NoteType` 参数，固定创建 rich_text 类型
- [x] 3.4 移除桌面端和移动端编辑面板中的 Markdown 编辑器条件渲染，只保留 RichTextEditor
- [x] 3.5 笔记卡片和搜索结果中的图标统一为 `Icons.text_fields`

## 4. 修改 editor_screen.dart

- [x] 4.1 移除 `markdown_editor.dart` 的 import
- [x] 4.2 移除编辑面板中的 Markdown 编辑器条件渲染，只保留 RichTextEditor
- [x] 4.3 简化 `_extractTitle` 方法：移除 Markdown 标题提取分支

## 5. 清理依赖

- [x] 5.1 从 `pubspec.yaml` 移除 `flutter_markdown` 和 `markdown` 依赖
- [x] 5.2 运行 `flutter pub get`

## 6. 验证

- [x] 6.1 运行 `flutter analyze` 确保无错误
- [x] 6.2 运行 `flutter test` 确保测试通过
