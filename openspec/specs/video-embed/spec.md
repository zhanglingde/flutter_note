## ADDED Requirements

### Requirement: 视频嵌入 Delta 格式
视频 SHALL 以 `BlockEmbed('video', jsonData)` 格式嵌入 Quill Delta，其中 jsonData 为 JSON 字符串 `{"source": "路径或URL", "width": 400}`。source 字段 SHALL 同时支持本地文件路径和网络 URL。

#### Scenario: 插入本地视频
- **WHEN** 用户选择本地视频文件并确认插入
- **THEN** 视频文件被保存到 `videos/{noteId}/` 目录，Delta 中插入 `BlockEmbed('video', '{"source": "本地路径", "width": 400}')`

#### Scenario: 插入网络视频
- **WHEN** 用户输入视频 URL 并确认插入
- **THEN** Delta 中插入 `BlockEmbed('video', '{"source": "URL", "width": 400}')`

### Requirement: 视频播放器渲染
视频嵌入 SHALL 使用自定义 `EmbedBuilder` 渲染视频播放器。本地文件 SHALL 使用 media_kit 播放，网络 URL SHALL 根据 source 路径判断播放方式。视频 SHALL 支持播放/暂停控制，并占据编辑器全宽显示。

#### Scenario: 渲染本地视频
- **WHEN** 编辑器遇到 source 为本地路径的视频 embed
- **THEN** 使用 media_kit 渲染视频播放器，显示播放控制条

#### Scenario: 渲染网络视频
- **WHEN** 编辑器遇到 source 为 http/https URL 的视频 embed
- **THEN** 使用对应的播放器渲染网络视频流

#### Scenario: 视频文件不存在
- **WHEN** 本地视频文件路径无效或文件已被删除
- **THEN** 显示"视频文件未找到"的占位符

### Requirement: 视频文件存储服务
系统 SHALL 提供 `VideoStorageService`，将视频文件保存到 `{应用文档目录}/videos/{noteId}/{时间戳}.{扩展名}` 路径下。SHALL 提供保存、删除单文件、删除笔记全部关联视频的方法。

#### Scenario: 保存视频文件
- **WHEN** 用户插入一个本地视频文件（字节流）
- **THEN** 文件被保存到 `videos/{noteId}/` 目录，返回完整文件路径

#### Scenario: 删除笔记关联视频
- **WHEN** 笔记被删除
- **THEN** `videos/{noteId}/` 目录下所有视频文件被清理

### Requirement: 工具栏视频插入按钮
底部工具栏 SHALL 包含视频插入按钮（视频图标），点击后弹出对话框提供"从文件选择"和"输入 URL"两种方式。文件选择 SHALL 使用 `FilePicker.platform.pickFiles(allowedExtension: 视频格式)`。

#### Scenario: 从文件选择视频
- **WHEN** 用户点击视频按钮并选择"从文件"
- **THEN** 弹出文件选择器，过滤视频格式（mp4/mov/avi/webm/mkv），选择后插入视频

#### Scenario: 通过 URL 插入视频
- **WHEN** 用户点击视频按钮并选择"输入 URL"
- **THEN** 弹出 URL 输入框，用户输入视频链接后插入视频

### Requirement: HTML 剪藏支持 video 标签
`WebClipperService.convertHtmlToDelta` SHALL 处理 HTML `<video>` 标签，提取 `src` 属性或子 `<source>` 标签的视频 URL，生成视频 embed 节点。

#### Scenario: 提取 video 标签 src
- **WHEN** HTML 中包含 `<video src="https://example.com/video.mp4">`
- **THEN** 在 Delta 中插入视频 embed，source 为视频 URL

#### Scenario: 提取 source 子标签
- **WHEN** HTML 中包含 `<video><source src="video.mp4" type="video/mp4"></video>`
- **THEN** 使用第一个 source 标签的 src 作为视频 URL

### Requirement: Markdown 双向转换支持视频
Delta 转 Markdown SHALL 将视频 embed 输出为 `![video](source)` 格式。Markdown 转 Delta SHALL 识别 `![video](url)` 模式并转为视频 embed（与图片 `![alt](url)` 区分通过 alt 文本包含 "video" 关键字）。

#### Scenario: Delta 转视频 Markdown
- **WHEN** Delta 中包含视频 embed（source 为 URL）
- **THEN** 输出 Markdown `![video](URL)`

#### Scenario: Markdown 视频转 Delta
- **WHEN** Markdown 中包含 `![video](https://example.com/video.mp4)`
- **THEN** 转为视频 embed `BlockEmbed('video', ...)`
