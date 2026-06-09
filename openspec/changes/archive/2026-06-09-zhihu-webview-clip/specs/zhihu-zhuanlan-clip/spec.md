## ADDED Requirements

### Requirement: URL 匹配知乎专栏文章
提取器 SHALL 匹配 host 为 `zhuanlan.zhihu.com` 且路径匹配 `/p/{id}` 模式的 URL，其中 `{id}` 为数字。

#### Scenario: 匹配标准专栏文章 URL
- **WHEN** URL 为 `https://zhuanlan.zhihu.com/p/1995787568894202157`
- **THEN** `canExtract` 返回 `true`

#### Scenario: 不匹配知乎问答 URL
- **WHEN** URL 为 `https://www.zhihu.com/question/123456`
- **THEN** `canExtract` 返回 `false`

#### Scenario: 不匹配非知乎域名
- **WHEN** URL 为 `https://example.com/p/123`
- **THEN** `canExtract` 返回 `false`

### Requirement: 从页面提取标题
提取器 SHALL 从 HTML 的 `<title>` 标签提取文章标题，并作为 `ClipMetadata.title` 返回。

#### Scenario: 提取 title 标签内容
- **WHEN** 页面 HTML 包含 `<title>知乎专栏文章标题</title>`
- **THEN** 返回的 `ClipMetadata.title` 为 `"知乎专栏文章标题"`

### Requirement: 从 js-initialData 提取正文内容
提取器 SHALL 从 `<script id="js-initialData" type="text/json">` 标签中解析 JSON，按路径 `initialState.entities.articles.{articleId}.content` 提取正文 HTML，其中 articleId 从 URL 路径 `/p/{id}` 中获取。

#### Scenario: 成功提取正文
- **WHEN** URL 为 `https://zhuanlan.zhihu.com/p/1995787568894202157`，且页面包含 `js-initialData` 脚本标签
- **THEN** 从 JSON 路径 `initialState.entities.articles.1995787568894202157.content` 提取 HTML 正文

#### Scenario: js-initialData 不存在
- **WHEN** 页面 HTML 中不存在 `<script id="js-initialData">` 标签
- **THEN** 返回 `ClipResult.failure`，包含描述性错误信息

#### Scenario: JSON 中无对应文章 ID
- **WHEN** JSON 解析成功但 `articles` 中不存在 URL 对应的文章 ID
- **THEN** 返回 `ClipResult.failure`，包含描述性错误信息

### Requirement: 将 HTML 正文转换为 Quill Delta
提取器 SHALL 使用 `WebClipperService.convertHtmlToDelta` 将提取的 HTML 正文转换为 Quill Delta 格式。Delta 结构 SHALL 为：标题（h1）+ URL 链接 + 正文内容。

#### Scenario: HTML 转换为 Delta
- **WHEN** 成功提取文章 HTML 正文
- **THEN** 生成包含标题（header:1）、URL 链接、正文内容的 Delta

### Requirement: 作为 WebView 提取器运行
提取器 SHALL 使用 `WebViewExtractorMixin`，设置 `requiresWebView` 为 `true`，通过 JS 注入在 WebView 中提取页面数据。

#### Scenario: WebView 环境要求
- **WHEN** 注册中心查询 `matchWebView(url)` 传入知乎专栏 URL
- **THEN** 返回此提取器实例

#### Scenario: 非 WebView 环境降级
- **WHEN** 通过 `extract()` 方法在非 WebView 环境调用
- **THEN** 返回 `ClipResult.failure`，提示需要 WebView 环境

### Requirement: 在应用启动时注册
提取器 SHALL 在应用启动时通过 `_initClipperRegistry()` 注册到 `ExtractorRegistry`，优先级为 10。

#### Scenario: 注册并匹配
- **WHEN** 应用启动后，用户输入 `https://zhuanlan.zhihu.com/p/1995787568894202157` 进行剪藏
- **THEN** 注册中心匹配到 `ZhihuZhuanlanExtractor` 并通过 WebView 提取内容
