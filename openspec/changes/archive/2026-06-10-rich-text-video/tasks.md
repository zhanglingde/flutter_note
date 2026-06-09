## 1. 依赖与基础设施

- [x] 1.1 在 `pubspec.yaml` 添加 `media_kit`、`media_kit_video`、`media_kit_libs_video`、`media_kit_libs_android_video` 依赖
- [x] 1.2 在 `lib/main.dart` 初始化 `MediaKit`（`MediaKit.ensureInitialized()`）
- [x] 1.3 创建 `lib/services/video_storage_service.dart`，实现 `saveVideo`、`deleteVideo`、`deleteVideosForNote` 方法

## 2. 视频嵌入构建器

- [x] 2.1 在 `rich_text_editor.dart` 创建 `_VideoEmbedBuilder`（实现 `EmbedBuilder`），注册 `'video'` key
- [x] 2.2 实现 `VideoPlayer` 组件：本地文件使用 media_kit 播放器，网络 URL 同样使用 media_kit
- [x] 2.3 实现视频占位符（文件不存在时显示"视频文件未找到"）
- [x] 2.4 Web 平台使用 `HtmlElementView` 嵌入 HTML5 `<video>` 标签

## 3. 视频插入入口

- [x] 3.1 在顶部工具栏添加视频图标按钮（位于图片按钮之后）
- [x] 3.2 实现视频插入对话框，支持"从文件选择"和"输入 URL"两个 tab
- [x] 3.3 实现文件选择逻辑：`FilePicker.platform.pickFiles(allowedExtension: 视频格式)`
- [x] 3.4 实现 `_insertVideo` 方法：保存视频文件 → 构建 `BlockEmbed('video', jsonData)` → 插入 Delta

## 4. HTML 剪藏扩展

- [x] 4.1 在 `web_clipper_service.dart` 的 `_processNode` 中添加 `case 'video':` 处理分支

## 5. Markdown 双向转换

- [x] 5.1 在 `delta_to_markdown.dart` 中添加视频 embed 的 Markdown 输出（`![video](url)`）
- [x] 5.2 在 `markdown_to_delta.dart` 中添加 `![video](url)` 的视频 embed 识别

## 6. 清理与集成

- [x] 6.1 在 `editor_screen.dart` 和 `home_screen.dart` 中笔记删除时调用 `VideoStorageService.deleteVideosForNote`
- [x] 6.2 运行 `flutter analyze` 确保无静态分析错误
- [ ] 6.3 Windows 平台手动测试视频插入和播放
