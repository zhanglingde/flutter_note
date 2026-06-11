## Why

笔记列表（列表视图和瀑布流视图）目前仅展示标题、预览文字和日期，无法直观识别包含图片或视频的笔记。添加缩略图可以提升笔记辨识度和浏览体验，尤其在瀑布流视图中缩略图能显著丰富卡片视觉效果。

## What Changes

- 解析笔记 delta JSON 内容，提取第一个图片或视频嵌入的 source 路径
- 在列表视图的笔记卡片中显示缩略图（左侧小图）
- 在瀑布流视图的笔记卡片中显示缩略图（顶部大图）
- 视频缩略图使用视频文件的第一帧，若提取失败则显示视频图标占位

## Capabilities

### New Capabilities
- `note-media-thumbnail`: 从笔记内容中提取首个媒体资源路径并在列表/瀑布流卡片中展示缩略图的能力

### Modified Capabilities

（无现有 spec 需要修改）

## Impact

- `lib/screens/home_screen.dart` — `_buildNoteCard`、`_buildWaterfallCard` 需要增加缩略图显示
- 可能新增 `lib/utils/media_thumbnail.dart` 工具方法用于从 delta 中提取媒体路径
- 视频缩略图可能需要新增依赖（如 `video_thumbnail` 或使用 `media_kit` 截帧）
- `lib/services/image_storage_service.dart` 和 `video_storage_service.dart` 可能需要新增获取首张/首个文件的方法
