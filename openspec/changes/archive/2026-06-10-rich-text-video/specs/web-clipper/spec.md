## ADDED Requirements

### Requirement: HTML video 标签转换为视频 embed
HTML 转 Delta 过程中，遇到 `<video>` 标签 SHALL 提取视频源 URL 并生成视频 embed 节点，而非跳过或仅提取文本。

#### Scenario: 处理带 src 的 video 标签
- **WHEN** HTML 中包含 `<video src="url">`
- **THEN** 生成 `BlockEmbed('video', '{"source": "url", "width": 400}')`

#### Scenario: 处理带 source 子标签的 video
- **WHEN** HTML 中包含 `<video><source src="url"></video>`
- **THEN** 使用第一个 source 的 src 生成视频 embed
