## ADDED Requirements

### Requirement: WebView 加载知乎页面
系统 SHALL 使用 WebView 加载用户填入的知乎问答链接，在真实浏览器环境中获取页面内容和合法的 Cookie/Session 状态。

#### Scenario: 加载知乎问答页面
- **WHEN** 用户输入一个知乎问答 URL（如 `https://www.zhihu.com/question/12345`）并确认
- **THEN** 系统 SHALL 在 WebView 中加载该 URL，并显示加载状态

#### Scenario: 加载失败回退
- **WHEN** WebView 加载超过 15 秒或发生网络错误
- **THEN** 系统 SHALL 提示加载失败并回退到通用 HTTP 剪藏方案

### Requirement: 拦截知乎 Feeds API 响应
系统 SHALL 在 WebView 加载知乎页面时，通过 JavaScript 注入拦截 `/api/v4/questions/$questionId/feeds` 接口的响应数据。

#### Scenario: 成功拦截 Feeds API 响应
- **WHEN** WebView 中的知乎页面发起对 `/api/v4/questions/{id}/feeds` 的请求并返回 JSON 数据
- **THEN** 系统 SHALL 捕获该 JSON 响应并通过 JavaScript 回调传递给 Dart 层

#### Scenario: 页面未触发 Feeds API
- **WHEN** WebView 页面加载完成但 10 秒内未检测到 Feeds API 请求
- **THEN** 系统 SHALL 回退到通用 HTTP 剪藏方案

### Requirement: 从拦截数据解析知乎内容
系统 SHALL 从拦截到的 Feeds API JSON 响应中解析出问题标题和回答正文，转换为 Quill Delta 格式。

#### Scenario: 解析指定回答
- **WHEN** URL 中包含 answerId（如 `/question/12345/answer/67890`）
- **THEN** 系统 SHALL 从 API 响应中匹配对应 answerId 的回答，提取标题和正文

#### Scenario: 解析首个回答
- **WHEN** URL 中仅包含 questionId（如 `/question/12345`）
- **THEN** 系统 SHALL 取 API 响应中的第一个回答，提取标题和正文

#### Scenario: 返回 ClipResult
- **WHEN** 解析完成
- **THEN** 系统 SHALL 返回包含 Quill Delta 的 `ClipResult`，格式与现有剪藏流程一致（标题 H1 + 正文内容）

### Requirement: 平台兼容性
系统 SHALL 根据运行平台选择合适的剪藏策略。

#### Scenario: Android/Windows 平台
- **WHEN** 应用运行在 Android 或 Windows 平台
- **THEN** 知乎链接 SHALL 使用 WebView 拦截方案

#### Scenario: Web 平台
- **WHEN** 应用运行在 Web 平台
- **THEN** 知乎链接 SHALL 回退到现有的 HTTP 请求方案

### Requirement: URL 识别
系统 SHALL 正确识别知乎问答 URL 并提取 questionId 和可选的 answerId。

#### Scenario: 识别标准知乎问答 URL
- **WHEN** 用户输入 `https://www.zhihu.com/question/12345`
- **THEN** 系统 SHALL 识别为知乎链接，提取 questionId 为 `12345`

#### Scenario: 识别带回答的知乎 URL
- **WHEN** 用户输入 `https://www.zhihu.com/question/12345/answer/67890`
- **THEN** 系统 SHALL 提取 questionId 为 `12345`，answerId 为 `67890`

#### Scenario: 识别知乎专栏 URL
- **WHEN** 用户输入知乎专栏链接（如 `https://zhuanlan.zhihu.com/p/12345`）
- **THEN** 系统 SHALL 走通用剪藏流程，不使用 WebView 拦截
