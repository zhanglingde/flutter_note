## Context

当前知乎剪藏通过 `http` 包直接发送 HTTP 请求：先 GET 页面获取 Cookie，再携带 Cookie 调用 `/api/v4/questions/{id}/feeds` API。该方案面临知乎反爬策略（UA 检测、JS 挑战、IP 限制）导致频繁失败。

项目支持 Android、Web、Windows 三个平台，其中 Web 平台无法嵌入原生 WebView，Android 和 Windows 支持。

## Goals / Non-Goals

**Goals:**
- 通过 WebView 加载知乎页面，利用真实浏览器环境获取合法 Cookie 和 Session
- 拦截 `/api/v4/questions/$questionId/feeds` 响应，从中解析问答内容
- 保持与现有通用剪藏流程的一致性（返回 `ClipResult`）
- 支持 Android 和 Windows 平台

**Non-Goals:**
- 不处理知乎专栏（zhuanlan）链接，专栏继续走通用剪藏
- 不支持 Web 平台的 WebView 剪藏（Web 平台无法嵌入原生 WebView）
- 不实现登录功能，仅依赖游客状态
- 不缓存 WebView 实例，每次剪藏创建新的 WebView

## Decisions

### 1. WebView 库选择: `flutter_inappwebview`

**选择**: `flutter_inappwebview`

**理由**:
- 支持 Android 和 Windows（desktop 插件），覆盖本项目目标平台
- 提供 `shouldInterceptAjaxRequest` / `onLoadResource` 等 API 拦截能力
- 可拦截响应体内容，这是 `webview_flutter` 不直接支持的
- 社区活跃，文档完善

**备选方案**:
- `webview_flutter`: 官方插件但拦截能力弱，无法直接获取响应体，需要通过 JavaScript 注入 workaround
- `webview_windows`: 仅支持 Windows，不覆盖 Android

### 2. 拦截策略: JavaScript 注入拦截 XMLHttpRequest

**选择**: 通过注入 JavaScript 拦截 `XMLHttpRequest` 和 `fetch` 的响应

**理由**:
- 知乎页面通过 XHR/fetch 调用 Feeds API
- 在页面加载前注入 JS 裡一层的 XHR 代理，捕获指定 URL 的响应
- 捕获到目标响应后通过 `JavaScriptHandlerCallback` 回传给 Dart 层

**备选方案**:
- `shouldInterceptAjaxRequest`: flutter_inappwebview 提供的原生拦截器，但配置复杂且在某些平台上行为不一致
- 代理服务器: 本地起 HTTP 代理拦截流量，过度设计

### 3. UI 流程: 对话框内嵌 WebView

**选择**: 将 WebView 嵌入到新的全屏/对话框页面中，显示加载状态

**理由**:
- 用户可以看到页面加载进度，知道应用在工作
- 加载完成后自动关闭并返回结果，无需用户手动操作
- 比后台静默加载更直观

### 4. 超时和错误处理

- WebView 加载超时: 15 秒
- API 拦截超时: 页面加载完成后等待 10 秒，若未捕获到目标 API 响应则回退到通用剪藏
- WebView 加载失败: 提示用户并回退到通用剪藏方案

## Risks / Trade-offs

- **[WebView 体积增大]** → `flutter_inappwebview` 会增加应用包体积（Android 约增加 2-3MB），可接受
- **[Windows WebView 依赖 Edge WebView2]** → Windows 上依赖系统安装的 Edge WebView2 Runtime，Win11 已内置，Win10 需用户安装。在应用文档中说明依赖即可
- **[知乎前端变更]** → 若知乎修改 API 路径或请求方式，拦截逻辑需同步更新。通过配置化 API 路径前缀降低维护成本
- **[Web 平台不可用]** → Web 平台不支持 WebView，知乎剪藏在 Web 上回退到通用 HTTP 方案
