## 1. 依赖与基础设置

- [x] 1.1 在 `pubspec.yaml` 中添加 `flutter_inappwebview` 依赖并运行 `flutter pub get`
- [x] 1.2 验证 `flutter_inappwebview` 在 Android 和 Windows 平台编译通过

## 2. WebView 拦截服务

- [x] 2.1 创建 `lib/services/zhihu_webview_service.dart`，实现 WebView 页面加载知乎 URL 的逻辑
- [x] 2.2 实现 JavaScript 注入：在页面加载前注入 XHR/fetch 代理脚本，拦截 `/api/v4/questions/*/feeds` 响应
- [x] 2.3 实现拦截数据回传：通过 `JavaScriptHandlerCallback` 将捕获的 JSON 响应传递给 Dart 层
- [x] 2.4 实现超时机制：WebView 加载超时 15 秒、API 拦截等待超时 10 秒，超时后回退通用剪藏
- [x] 2.5 实现从拦截的 JSON 中解析 questionId/answerId 并提取标题和正文内容
- [x] 2.6 实现将解析结果转换为 `ClipResult`（Quill Delta 格式），复用现有的 `_convertToDelta` 逻辑

## 3. UI 集成

- [x] 3.1 创建 WebView 剪藏页面组件（显示加载状态、进度指示器）
- [x] 3.2 修改 `rich_text_editor.dart` 中的 `_clipWebPage` 方法，知乎链接走 WebView 流程
- [x] 3.3 修改 `WebClipperService.fetchAndConvert` 或新增路由方法，根据平台和 URL 类型分发到 WebView 或 HTTP 方案

## 4. 平台兼容

- [x] 4.1 实现 Web 平台检测，Web 平台知乎链接回退到现有 HTTP 方案
- [x] 4.2 确保专栏链接（zhuanlan.zhihu.com）始终走通用剪藏，不触发 WebView 流程

## 5. 清理与测试

- [x] 5.1 移除 `_clipZhihu` 方法中的旧 HTTP 两步请求逻辑（替换为调用 WebView 服务）
- [ ] 5.2 在 Android 设备上端到端测试知乎问答剪藏
- [ ] 5.3 在 Windows 上端到端测试知乎问答剪藏
- [ ] 5.4 测试超时和失败场景的回退行为
- [x] 5.5 运行 `flutter analyze` 确保无静态分析错误
