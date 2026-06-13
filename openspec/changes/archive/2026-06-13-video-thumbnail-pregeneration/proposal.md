## Why

视频在编辑器和列表中显示有明显延迟——每次渲染都需要等待 media_kit Player 初始化才能显示画面。列表/瀑布流视图更是直接使用灰色占位符+播放图标，无法展示视频实际内容。图片则通过直接文件读取实现即时显示，视频应达到同样体验。

## What Changes

- 视频插入时使用 `media_kit` Player 的 `screenshot()` API 预生成 JPEG 缩略图
- Delta JSON 中视频 embed 数据增加 `thumbnail` 字段存储缩略图路径
- 编辑器中视频优先显示静态缩略图+播放按钮，点击后初始化播放器
- 列表和瀑布流卡片使用真实视频帧替代灰色占位符
- 向后兼容：无 `thumbnail` 字段的旧视频回退到现有播放器模式

## Capabilities

### New Capabilities
- `video-thumbnail-generation`: 缩略图生成能力——在视频插入时截取 JPEG 帧，存储为缩略图文件，管理缩略图生命周期（生成、路径推导、删除联动）

### Modified Capabilities
- `video-embed`: Delta JSON 格式增加 `thumbnail` 字段；`_VideoEmbedBuilder` 渲染逻辑从直接初始化播放器改为优先显示缩略图
- `note-media-thumbnail`: `MediaInfo` 增加 `thumbnail` 字段；`extractFirstMedia` 提取缩略图路径；列表和瀑布流卡片使用真实缩略图替代灰色占位符

## Impact

- **代码文件**: `video_storage_service.dart`（新增 generateThumbnail 方法）、`rich_text_editor.dart`（_VideoEmbedBuilder 渲染逻辑变更）、`media_thumbnail.dart`（MediaInfo 和 extractFirstMedia 扩展）、`home_screen.dart`（列表/瀑布流缩略图渲染）
- **数据格式**: Delta JSON 视频 embed 增加 `thumbnail` 可选字段，向后兼容
- **依赖**: 已有 `media_kit` 依赖，无需新增
- **存储**: 每个视频额外生成一个 JPEG 缩略图文件（约几十 KB），与视频同目录存储
