## Context

当前富文本编辑器使用 flutter_quill 11.5.0，图片通过自定义 `BlockEmbed('image', jsonData)` + 自定义 `EmbedBuilder` 实现，不依赖 `flutter_quill_extensions`。图片文件存储在 `images/{noteId}/` 目录下，由 `ImageStorageService` 管理。flutter_quill 内置了 `BlockEmbed.videoType = 'video'`，可直接使用。

项目支持 Windows、Android、Web 三个平台，视频播放需要跨平台兼容。

## Goals / Non-Goals

**Goals:**
- 在笔记中插入和播放视频（本地文件和网络 URL）
- 复用现有图片架构模式（BlockEmbed + EmbedBuilder + 本地存储）
- 工具栏提供视频插入入口
- HTML 剪藏支持 `<video>` 标签
- Markdown 双向转换支持视频

**Non-Goals:**
- 不支持视频录制
- 不支持视频编辑/裁剪
- 不支持视频上传到云端
- 不实现视频缩略图生成
- 不使用 `flutter_quill_extensions`（保持与自定义图片方案的一致性）

## Decisions

### D1: 使用 media_kit 而非 video_player 作为视频播放器

**选择**: 使用 `media_kit` + `media_kit_video` + `media_kit_libs_video`

**理由**: `media_kit` 基于 libmpv/FFmpeg，在 Windows 桌面上提供原生级性能和格式支持。`video_player` 在 Windows 上依赖 `media_kit` 作为底层实现（自 video_player 2.8+ 起），直接使用 media_kit 避免额外中间层。对于 Android 使用 `media_kit_libs_android_video`，Web 平台回退到 HTML5 `<video>` 标签。

**备选方案**: `video_player` — 在 Windows 上底层也是 media_kit，增加不必要的间接层。

### D2: 自定义 EmbedBuilder 而非 flutter_quill_extensions

**选择**: 自定义 `_VideoEmbedBuilder`

**理由**: 项目已有自定义 `_ImageEmbedBuilder`（支持拖拽调整宽度、右键菜单、点击预览等），视频应保持一致的架构模式和交互风格。`flutter_quill_extensions` 会引入 `image_picker`、`url_launcher` 等项目不需要的依赖。

### D3: 视频存储服务独立于 ImageStorageService

**选择**: 新建 `VideoStorageService`

**理由**: 视频文件较大，目录结构独立（`videos/{noteId}/`），便于独立管理和清理。避免将图片和视频混在同一目录中。

### D4: Delta 中的视频数据格式

**选择**: JSON 格式 `{"source": "路径或URL", "width": 400}`，与图片格式一致

**理由**: 复用图片的解析逻辑，`source` 字段同时支持本地路径和网络 URL（通过 `source.startsWith('http')` 判断）。

### D5: 视频插入入口 — URL 输入 + 文件选择

**选择**: 在底部工具栏添加视频按钮，点击后弹出选择对话框，支持"从文件选择"和"输入 URL"两种方式

**理由**: 工具栏空间有限，两种来源合并为一个入口。URL 方式支持网络视频嵌入，文件选择支持本地视频导入。

### D6: Web 平台使用 HTML5 video 标签

**选择**: Web 平台使用 `HtmlElementView` 嵌入原生 `<video>` 标签

**理由**: media_kit 不支持 Web 平台。HtmlElementView 是 Flutter Web 嵌入 HTML 原生元素的标准方式，可利用浏览器内置的视频播放能力。

## Risks / Trade-offs

- **[视频文件体积大]** → 本地存储仅保存引用路径，不做文件大小限制（信任用户选择）
- **[Web 平台兼容性]** → Web 使用 HtmlElementView + HTML5 video，不支持时显示占位符
- **[格式兼容性]** → media_kit 支持 MP4/WebM/MOV/AVI 等主流格式，极少部分格式可能不支持
- **[向后兼容]** → 新增 embed 类型不影响现有 Delta 数据，旧笔记无需迁移
