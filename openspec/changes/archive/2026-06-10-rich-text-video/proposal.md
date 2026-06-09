## Why

当前富文本编辑器仅支持图片插入，用户无法在笔记中嵌入视频内容。笔记应用作为多媒体记录工具，支持视频是自然的功能扩展。现有图片架构（自定义 BlockEmbed + EmbedBuilder + 本地存储）提供了成熟的模式，视频可复用同一架构快速实现。

## What Changes

- 新增视频嵌入类型：使用 `BlockEmbed('video', ...)` 在 Delta 中嵌入视频，数据格式为 JSON `{"source": "路径", "width": 400}`
- 新增视频嵌入构建器：自定义 `EmbedBuilder` 渲染视频播放器，支持本地文件和网络 URL 两种来源
- 新增视频存储服务：参照 `ImageStorageService`，使用 `videos/{noteId}/` 目录存储本地视频文件
- 新增工具栏视频按钮：在底部工具栏添加视频插入按钮，支持从文件选择和 URL 输入
- 扩展 HTML 剪藏：`WebClipperService.convertHtmlToDelta` 增加 `<video>` 标签处理
- 扩展 Markdown 转换：Delta ↔ Markdown 双向支持视频嵌入

## Capabilities

### New Capabilities
- `video-embed`: 视频嵌入能力，包括本地/网络视频插入、视频播放器渲染、视频文件存储、工具栏入口

### Modified Capabilities
- `rich-text-editing`: 新增视频相关工具栏操作
- `web-clipper`: HTML 转 Delta 增加 video 标签处理

## Impact

- **新增文件**: `lib/services/video_storage_service.dart`
- **修改文件**: `lib/widgets/rich_text_editor.dart`（视频嵌入构建器、工具栏按钮、插入方法）、`lib/services/web_clipper_service.dart`（video 标签处理）、`lib/utils/delta_to_markdown.dart`（视频输出）、`lib/utils/markdown_to_delta.dart`（视频输入）、`lib/screens/editor_screen.dart` 和 `lib/screens/home_screen.dart`（笔记删除时清理视频文件）、`lib/main.dart`（注册 VideoStorageService）
- **新增依赖**: `video_player` 包（视频播放）、`media_kit` + `media_kit_video`（桌面平台视频播放）
