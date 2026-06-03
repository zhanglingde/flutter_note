## Why

当前知乎剪藏通过 HTTP 直接请求页面获取 Cookie，再调用 Feeds API 获取回答内容。这种方式容易被知乎反爬策略拦截（返回 403/验证码），导致剪藏失败率高。通过 WebView 加载知乎页面并拦截 API 响应，可以利用浏览器的真实环境绕过反爬限制，获得与浏览器访问一致的 Cookie 和 Session 状态。

## What Changes

- 新增 WebView 页面用于加载知乎 URL，作为剪藏流程的中间步骤
- 在 WebView 中拦截 `/api/v4/questions/$questionId/feeds` 接口的网络请求响应
- 从拦截到的 JSON 响应中解析知乎问答内容（标题、回答正文）
- 替换当前 `_clipZhihu` 方法中的两步 HTTP 请求实现，改为 WebView 拦截方案
- 新增 WebView 依赖（`flutter_inappwebview` 或类似库）

## Capabilities

### New Capabilities
- `webview-interceptor`: WebView 加载网页并拦截指定 API 请求响应的能力，支持从拦截到的 JSON 数据中提取结构化内容

### Modified Capabilities
（无现有 specs 目录下的能力规范，全部为新增）

## Impact

- **依赖变更**: 需新增 WebView 相关 Flutter 插件（`flutter_inappwebview`），影响 `pubspec.yaml`
- **平台兼容性**: WebView 在 Android 和 Windows 上行为可能不同，需分别测试；Web 平台不支持 WebView 嵌入
- **UI 变更**: 剪藏知乎链接时会显示 WebView 页面（加载中状态），而非静默后台请求
- **代码影响**: `web_clipper_service.dart` 中的 `_clipZhihu` 方法将重写，`rich_text_editor.dart` 中的 `_clipWebPage` 方法需适配 WebView 异步流程
