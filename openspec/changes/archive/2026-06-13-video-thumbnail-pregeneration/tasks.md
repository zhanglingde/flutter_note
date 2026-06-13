## 1. 缩略图生成服务

- [x] 1.1 在 `VideoStorageService` 中新增 `generateThumbnail(String source, String noteId, {int seekMs = 0})` 方法：创建临时 Player → open Media → 等待就绪 → screenshot → 保存 JPEG → dispose Player → 返回路径
- [x] 1.2 实现缩略图文件命名规则：`thumb_{视频文件名去扩展名}.jpg`，存储在 `videos/{noteId}/` 目录
- [x] 1.3 修改 `deleteVideo(filePath)` 方法，删除视频时同时删除对应缩略图文件（推导路径）
- [x] 1.4 添加 Web 平台判断：Web 平台直接返回 null，不创建 Player

## 2. 视频插入流程集成

- [x] 2.1 修改 `_insertVideo` 方法：视频保存后调用 `generateThumbnail`，成功时将 thumbnail 路径写入 BlockEmbed JSON
- [x] 2.2 修改 `_insertVideoUrl` 方法：网络视频跳过缩略图生成（截帧可能失败），保持现有 JSON 格式
- [x] 2.3 缩略图生成失败时不阻塞插入流程，不写入 thumbnail 字段

## 3. 编辑器缩略图渲染

- [x] 3.1 修改 `_VideoEmbedBuilder.build()`：解析 embed 数据提取 thumbnail 字段，有缩略图时显示静态图片+播放按钮覆盖层
- [x] 3.2 实现缩略图状态 Widget：显示 `Image.file(thumbnailPath)` + 居中半透明播放按钮图标
- [x] 3.3 点击播放按钮时切换为 `_VideoPlayerWidget`，播放器 dispose 后回到缩略图状态
- [x] 3.4 缩略图文件丢失时（`Image.file` errorBuilder）回退到直接初始化播放器模式
- [x] 3.5 无 thumbnail 字段的旧数据保持现有 `_VideoPlayerWidget` 行为不变

## 4. 列表缩略图提取与显示

- [x] 4.1 扩展 `MediaInfo` 类，新增 `thumbnail` 字段（String?）
- [x] 4.2 修改 `extractFirstMedia` 函数，解析 delta 时同时提取 thumbnail 路径并填入 `MediaInfo`
- [x] 4.3 修改 `_buildListThumbnail`：视频有 thumbnail 时显示 `Image.file(thumbnail)` + 播放图标，无 thumbnail 保持灰色占位符
- [x] 4.4 修改 `_buildWaterfallThumbnail`：视频有 thumbnail 时显示真实帧图像 + 播放图标，无 thumbnail 保持灰色占位符
- [x] 4.5 `Image.file` 加载缩略图失败时回退到灰色占位符+播放图标

## 5. 验证

- [x] 5.1 验证本地视频插入时缩略图正确生成并保存
- [x] 5.2 验证编辑器中视频显示缩略图+播放按钮，点击可播放
- [x] 5.3 验证列表和瀑布流视图显示真实视频帧缩略图
- [x] 5.4 验证旧数据（无 thumbnail 字段）回退到现有行为
- [x] 5.5 验证删除视频时缩略图一并被删除
