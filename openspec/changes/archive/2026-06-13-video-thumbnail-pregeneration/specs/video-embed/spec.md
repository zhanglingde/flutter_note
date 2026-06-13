## MODIFIED Requirements

### Requirement: 视频嵌入 Delta 格式
视频 SHALL 以 `BlockEmbed('video', jsonData)` 格式嵌入 Quill Delta，其中 jsonData 为 JSON 字符串。JSON SHALL 包含 `source`（路径或 URL）、`width`（宽度）和可选的 `thumbnail`（缩略图文件绝对路径）字段。格式：`{"source": "路径或URL", "width": 400, "thumbnail": "缩略图路径"}`。

#### Scenario: 插入本地视频（含缩略图）
- **WHEN** 用户选择本地视频文件并确认插入，且缩略图生成成功
- **THEN** 视频文件被保存到 `videos/{noteId}/` 目录，Delta 中插入 `BlockEmbed('video', '{"source": "本地路径", "width": 400, "thumbnail": "缩略图路径"}')`

#### Scenario: 插入本地视频（缩略图生成失败）
- **WHEN** 用户选择本地视频文件并确认插入，但缩略图生成失败
- **THEN** Delta 中插入 `BlockEmbed('video', '{"source": "本地路径", "width": 400}')`，无 thumbnail 字段

#### Scenario: 插入网络视频
- **WHEN** 用户输入视频 URL 并确认插入
- **THEN** Delta 中插入 `BlockEmbed('video', '{"source": "URL", "width": 400}')`，无 thumbnail 字段

#### Scenario: 旧数据兼容（无 thumbnail 字段）
- **WHEN** 编辑器遇到不含 thumbnail 字段的视频 embed
- **THEN** 回退到直接初始化 media_kit 播放器渲染

### Requirement: 视频播放器渲染
视频嵌入 SHALL 使用自定义 `EmbedBuilder` 渲染。当 embed 数据包含 `thumbnail` 字段时，SHALL 优先显示静态缩略图图片加居中播放按钮覆盖层。点击播放按钮后 SHALL 切换为 media_kit 播放器。播放器关闭后 SHALL 回到缩略图显示状态。无 thumbnail 字段时 SHALL 保持现有直接初始化播放器的行为。

#### Scenario: 有缩略图时显示静态缩略图
- **WHEN** 编辑器遇到包含 thumbnail 字段且缩略图文件存在的视频 embed
- **THEN** 显示缩略图图片，居中显示半透明播放按钮图标

#### Scenario: 点击播放按钮切换到播放器
- **WHEN** 用户点击缩略图上的播放按钮
- **THEN** 替换缩略图为 media_kit 播放器，开始播放视频

#### Scenario: 播放器关闭后回到缩略图
- **WHEN** 用户关闭或停止播放器
- **THEN** 播放器被 dispose，显示恢复为静态缩略图+播放按钮

#### Scenario: 缩略图文件丢失时回退
- **WHEN** thumbnail 字段存在但缩略图文件不存在
- **THEN** 回退到直接初始化 media_kit 播放器渲染（与无 thumbnail 字段行为一致）

#### Scenario: 渲染网络视频
- **WHEN** 编辑器遇到 source 为 http/https URL 的视频 embed
- **THEN** 使用对应的播放器渲染网络视频流

#### Scenario: 视频文件不存在
- **WHEN** 本地视频文件路径无效或文件已被删除
- **THEN** 显示"视频文件未找到"的占位符
