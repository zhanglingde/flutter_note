# 视频缩略图预生成设计

## 背景

当前视频在编辑器和列表中显示有延迟——需要等待 media_kit Player 初始化后才能渲染。图片因为是直接文件读取，显示即时。目标是让视频也能像图片一样无延迟显示。

## 方案

使用 media_kit Player 的 `screenshot()` API，在视频插入时预生成 JPEG 缩略图。后续编辑器和列表直接显示缩略图图片，消除初始化延迟。

## 数据模型

### Delta JSON 格式

视频 BlockEmbed 数据增加 `thumbnail` 字段：

```json
{"source": "/path/to/video.mp4", "width": 400, "thumbnail": "/path/to/thumb_xxx.jpg"}
```

- `thumbnail`：缩略图文件绝对路径，插入时生成
- 向后兼容：无此字段时回退到播放器模式

### 缩略图存储

- 位置：与视频同目录 `{appDir}/videos/{noteId}/`
- 命名：`thumb_{timestamp}.jpg`（与视频文件同名加 `thumb_` 前缀）
- 示例：视频 `1718000000.mp4` → 缩略图 `thumb_1718000000.jpg`

## 缩略图生成

### 流程（在 `_insertVideo` / `_insertVideoUrl` 中）

1. 保存视频文件或获取 source URL
2. 创建临时 `Player`，`open(Media(source), play: false)`
3. 等待 Player 就绪（监听 `width`/`height` stream）
4. 调用 `player.screenshot(format: 'image/jpeg')` 获取 JPEG bytes
5. 保存为 `thumb_{timestamp}.jpg`
6. 将 `thumbnail` 路径写入 BlockEmbed JSON
7. `dispose` 临时 Player

### 封装位置

`VideoStorageService` 新增方法：

```dart
Future<String?> generateThumbnail(String source, String noteId, {int seekMs = 0})
```

返回缩略图路径，失败返回 null。

### 删除联动

- `deleteVideo(filePath)`：同时删除对应缩略图（推导路径：同目录 `thumb_{name}.jpg`）
- `deleteVideosForNote(noteId)`：已删除整个目录，无需改动

## 编辑器显示

### `_VideoEmbedBuilder` 变更

1. 解析 embed 数据，提取 `thumbnail` 字段
2. 有缩略图：显示静态缩略图图片 + 居中播放按钮图标（半透明背景）
3. 点击播放按钮：切换为 `_VideoPlayerWidget`（media_kit 播放器）
4. 播放器 dispose 后：回到缩略图状态
5. 无缩略图（旧数据）：保持现有 `_VideoPlayerWidget` 行为

## 列表缩略图

扩展 `MediaInfo` 增加 `thumbnail` 字段。`extractFirstMedia` 解析 delta 时同时提取 `thumbnail`。列表和瀑布流卡片优先使用 `thumbnail` 路径显示缩略图。

## 错误处理

- 截帧失败：不阻塞视频插入，不写入 `thumbnail` 字段，回退播放器模式
- 缩略图文件丢失：`Image.file` 的 `errorBuilder` 回退到播放器模式或播放图标
- 网络视频截帧失败：同上，跳过缩略图
- 资源管理：每次截帧只创建一个临时 Player，用完立即释放
