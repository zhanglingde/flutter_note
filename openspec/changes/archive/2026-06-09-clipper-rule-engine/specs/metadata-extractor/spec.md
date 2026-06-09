## ADDED Requirements

### Requirement: Readability 正文提取
系统 SHALL 使用 `reader_mode` 包（Mozilla Readability.js 的 Dart 移植）作为通用正文提取引擎。

#### Scenario: 通用文章提取成功
- **WHEN** 传入一个包含文章内容的 HTML 字符串
- **THEN** 系统 SHALL 使用 `reader_mode` 的 `parse()` 方法提取正文，返回清理后的 HTML 内容

#### Scenario: 页面不可读
- **WHEN** 传入的 HTML 不包含可识别的文章内容（如登录页、导航页）
- **THEN** `isProbablyReaderable()` SHALL 返回 false，提取器 SHALL 返回失败 ClipResult

#### Scenario: Readability 返回元数据
- **WHEN** Readability 成功提取正文
- **THEN** 系统 SHALL 从返回的 `article` 对象中获取 title、byline（作者）、siteName、publishedTime、lang 等元数据

### Requirement: Readability 通用兜底提取器
系统 SHALL 提供 `ReadabilityExtractor`，作为无专用提取器和规则模板时的通用兜底。

#### Scenario: 任意 URL 通用提取
- **WHEN** 用户输入一个未被任何专用提取器或规则模板匹配的 URL
- **THEN** 系统 SHALL 通过 HTTP 获取 HTML，使用 Readability 提取正文，转换为 Quill Delta 格式返回

#### Scenario: 提取内容转换为 Delta
- **WHEN** Readability 返回清理后的 HTML 正文
- **THEN** 系统 SHALL 使用 `convertHtmlToDelta()` 将其转换为 Quill Delta 格式

#### Scenario: 提取失败回退
- **WHEN** Readability 无法提取有效内容（HTML 结构不包含文章）
- **THEN** 系统 SHALL 返回 `ClipResult.failure`，附带错误信息"无法提取该网页内容"

### Requirement: Meta 标签元数据提取
系统 SHALL 在 Readability 提取结果基础上，通过 meta 标签补充缺失的元数据字段。

#### Scenario: 补充描述信息
- **WHEN** Readability 未返回 description 且 HTML 包含 `og:description` 或 `meta[name=description]`
- **THEN** 系统 SHALL 从 meta 标签提取描述信息

#### Scenario: 补充封面图
- **WHEN** Readability 未返回封面图且 HTML 包含 `og:image` meta 标签
- **THEN** 系统 SHALL 从 meta 标签提取封面图 URL
