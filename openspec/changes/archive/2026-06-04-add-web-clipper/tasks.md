## 1. 依赖与基础设施

- [x] 1.1 在 `pubspec.yaml` 中添加 `http` 依赖包
- [x] 1.2 创建 `lib/services/web_clipper_service.dart`，实现通过 Jina Reader API 抓取网页正文的 `Future<String?> fetchWebContent(String url)` 方法
- [x] 1.3 创建 `lib/utils/markdown_to_delta.dart`，实现 Markdown 文本转 Quill Delta 操作列表的转换器

## 2. UI 组件

- [x] 2.1 创建 `lib/widgets/web_clipper_dialog.dart`，实现链接输入弹窗组件（包含 URL 输入框、确定/取消按钮）
- [x] 2.2 在弹窗中添加 URL 格式校验（非空、以 http/https 开头）

## 3. 工具栏集成

- [x] 3.1 在 `lib/widgets/rich_text_editor.dart` 的 `_buildToolbar()` 方法中，在左侧图片按钮之后添加 `LucideIcons.link2` 图标按钮（size: 20）
- [x] 3.2 添加 `_isClipping` 状态变量控制加载状态，加载时图标显示 `CircularProgressIndicator` 并禁用点击
- [x] 3.3 实现点击回调：弹出链接输入弹窗 → 调用 `WebClipperService` 抓取内容 → 转换为 Delta → 插入编辑器光标位置 → 附加来源链接
- [x] 3.4 添加错误处理：网络错误和 API 错误时显示 SnackBar 提示


