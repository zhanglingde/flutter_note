# WebView 拦截剪藏规格

### Requirement: WebView 加载知乎页面
系统 SHALL 使用通用 `ClipperWebViewPage` 加载用户填入的知乎问答链接，通过 `ZhihuExtractor` 提供器注入 JS 拦截脚本。

#### Scenario: 加载知乎问答页面
- **WHEN** 用户输入一个知乎问答 URL（如 `https://www.zhihu.com/question/12345`）并确认
- **THEN** 系统 SHALL 使用 `ClipperWebViewPage` 加载该 URL，注入 `ZhihuExtractor` 提供的 JS 脚本，并显示加载状态

#### Scenario: 加载失败回退
- **WHEN** WebView 加载超过 15 秒或发生网络错误
- **THEN** 系统 SHALL 提示加载失败并回退到 Readability 通用 HTTP 剪藏方案

### Requirement: 拦截知乎 Feeds API 响应
系统 SHALL 在 `ZhihuExtractor` 中定义 JS 拦截脚本，通过 `WebViewExtractor` mixin 提供给通用 WebView 页。

#### Scenario: 成功拦截 Feeds API 响应
- **WHEN** WebView 中的知乎页面发起对 `/api/v4/questions/{id}/feeds` 的请求并返回 JSON 数据
- **THEN** 系统 SHALL 通过 `WebViewExtractor` 的 `injectedScript` 捕获响应，通过 `handlerName` 回调传递给 Dart 层，由 `parseResponse` 解析

#### Scenario: 页面未触发 Feeds API
- **WHEN** WebView 页面加载完成但 10 秒内未检测到 Feeds API 请求
- **THEN** 系统 SHALL 回退到 Readability 通用 HTTP 剪藏方案

### Requirement: 从拦截数据解析知乎内容
系统 SHALL 在 `ZhihuExtractor.parseResponse()` 中解析 Feeds API JSON 响应，转换为 Quill Delta 格式。

#### Scenario: 解析指定回答
- **WHEN** URL 中包含 answerId（如 `/question/12345/answer/67890`）
- **THEN** 系统 SHALL 从 API 响应中匹配对应 answerId 的回答，提取标题和正文

#### Scenario: 解析首个回答
- **WHEN** URL 中仅包含 questionId（如 `/question/12345`）
- **THEN** 系统 SHALL 取 API 响应中的第一个回答，提取标题和正文

#### Scenario: 返回 ClipResult
- **WHEN** 解析完成
- **THEN** 系统 SHALL 返回包含 Quill Delta 和 `ClipMetadata` 的 `ClipResult`

### Requirement: 通用 WebView 提取页
系统 SHALL 提供通用 `ClipperWebViewPage`，接受任意实现了 `WebViewExtractor` mixin 的提取器。

#### Scenario: 接受提取器实例
- **WHEN** 注册中心匹配到需要 WebView 的提取器
- **THEN** 调用方 SHALL 使用该提取器创建 `ClipperWebViewPage`，页面自动注入提取器的 JS 脚本

#### Scenario: JS 回调结果解析
- **WHEN** WebView 触发 JavaScript 回调
- **THEN** `ClipperWebViewPage` SHALL 调用提取器的 `parseResponse()` 方法解析结果

#### Scenario: 超时处理
- **WHEN** WebView 加载或数据捕获超过超时时间
- **THEN** `ClipperWebViewPage` SHALL 返回 `ClipResult.failure`，调用方可选择降级到其他提取器

### Requirement: 小红书 WebView 提取
系统 SHALL 通过 `XhsExtractor` 实现 WebView meta 标签提取，使用通用 `ClipperWebViewPage`。

#### Scenario: 小红书页面提取
- **WHEN** 用户输入小红书 URL（如 `https://www.xiaohongshu.com/explore/12345`）
- **THEN** 系统 SHALL 使用 `ClipperWebViewPage` 加载页面，注入 `XhsExtractor` 提供的 JS 脚本提取 meta 标签数据

#### Scenario: 返回图文内容
- **WHEN** XhsExtractor 成功提取 meta 标签数据
- **THEN** 系统 SHALL 返回包含标题、描述文本和图片的 `ClipResult`，附带 `ClipMetadata`

### Requirement: 平台兼容性
系统 SHALL 根据运行平台选择合适的剪藏策略。

#### Scenario: Android/Windows 平台
- **WHEN** 应用运行在 Android 或 Windows 平台
- **THEN** 需要 WebView 的提取器（知乎、小红书）SHALL 使用 `ClipperWebViewPage`

#### Scenario: Web 平台
- **WHEN** 应用运行在 Web 平台
- **THEN** 注册中心 SHALL 自动跳过需要 WebView 的提取器，使用 Readability HTTP 提取
