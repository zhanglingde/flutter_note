## 1. 媒体提取工具方法

- [x] 1.1 在 `lib/utils/media_thumbnail.dart` 中创建 `MediaInfo` 类（`source`、`isVideo` 两个字段）
- [x] 1.2 实现 `extractFirstMedia(String content)` 方法，解析 delta JSON 提取首个图片/视频 source

## 2. 列表视图缩略图

- [x] 2.1 在 `_buildNoteCard` 中调用 `extractFirstMedia` 获取媒体信息
- [x] 2.2 为有媒体的笔记设置 `ListTile.leading`，图片显示 48x48 圆角缩略图，视频显示播放图标占位

## 3. 瀑布流视图缩略图

- [x] 3.1 在 `_buildWaterfallCard` 中调用 `extractFirstMedia` 获取媒体信息
- [x] 3.2 在卡片 Column 顶部添加缩略图区域：图片用 `ClipRRect` + `Image.file/network`，最大高度 120；视频用灰色背景 + 播放图标

## 4. 验证

- [x] 4.1 运行 `flutter analyze` 确认无警告
- [ ] 4.2 手动验证：含图片笔记在列表/瀑布流显示缩略图，含视频笔记显示播放图标，无媒体笔记无缩略图
