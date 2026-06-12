## Context

笔记内容以 Quill delta JSON 格式存储，图片和视频通过 `BlockEmbed` 嵌入：
- 图片: `{"insert": {"image": "{\"source\":\"path\",\"width\":400}"}}`
- 视频: `{"insert": {"video": "{\"source\":\"path\",\"width\":400}"}}`

source 可以是本地文件路径或网络 URL。项目已使用 `media_kit` 处理视频播放。

列表视图使用 `ListTile`，瀑布流视图使用自定义 `Container` 卡片，两者都在 `home_screen.dart` 中。

## Goals / Non-Goals

**Goals:**
- 从笔记 delta 中提取第一个媒体嵌入的 source
- 列表视图卡片左侧显示小缩略图（48x48）
- 瀑布流视图卡片顶部显示大缩略图（宽度撑满、高度自适应）
- 图片直接用 `Image.file` / `Image.network` 显示
- 视频显示播放图标叠加在占位图上

**Non-Goals:**
- 不对视频做真正的帧截取（复杂且需额外原生依赖）
- 不支持多张缩略图轮播
- 不支持缩略图点击预览
- 不缓存缩略图（直接读取文件）

## Decisions

### 1. 媒体提取：纯 Dart 解析 delta JSON

**选择**: 遍历 delta ops，找到第一个 `op['insert']` 为 Map 且包含 `image` 或 `video` key 的操作，解析其 JSON 字符串获取 source。

**理由**: 无需额外依赖，逻辑简单，与现有 `_extractTitle` 和 `_getPreview` 方法一致。

### 2. 视频缩略图：图标占位

**选择**: 视频使用 `Icons.play_circle_filled` 叠加在灰色背景上作为缩略图。

**备选**:
- `video_thumbnail` 包截取第一帧 — 需要原生代码，Windows 支持不完善
- `media_kit` 截帧 — API 复杂，需等待播放器初始化

**理由**: 避免引入额外原生依赖和复杂性，图标占位足够清晰表达"这是一个视频"。

### 3. 列表视图缩略图位置：ListTile.leading

**选择**: 使用 `ListTile` 的 `leading` 属性显示 48x48 圆角缩略图。

**理由**: `ListTile` 原生支持 leading，布局自动对齐。

### 4. 瀑布流缩略图位置：卡片顶部

**选择**: 在卡片 `Column` 的顶部添加 `ClipRRect` 包裹的图片，宽度撑满、高度按比例自适应，最大高度 120。

**理由**: 瀑布流卡片有足够空间展示大图，视觉效果好。

## Risks / Trade-offs

- [大量笔记时每个都解析 delta 可能有性能影响] → 缩略图提取方法轻量（只遍历到第一个媒体即停），且 Flutter 的 ListView builder 只构建可见项
- [网络图片在列表中加载可能慢] → 使用 `cached_network_image` 或接受默认加载行为，暂不额外优化
- [视频只显示图标不够直观] → 可在后续迭代中加入帧截取
