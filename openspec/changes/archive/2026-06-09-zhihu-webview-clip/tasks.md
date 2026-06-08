## 1. 创建 ZhihuZhuanlanExtractor

- [x] 1.1 创建 `lib/services/clipper/extractors/zhihu_zhuanlan_extractor.dart`，实现 `BaseExtractor with WebViewExtractor`
- [x] 1.2 实现 `canExtract(Uri url)` — 匹配 `zhuanlan.zhihu.com/p/{id}`
- [x] 1.3 实现 `injectedScript` — JS 脚本提取 `<title>` 和 `<script id="js-initialData">` 内容
- [x] 1.4 实现 `handlerName` — 定义回调名称
- [x] 1.5 实现 `parseResponse` — 解析 JSON，提取 articleId 对应的 content HTML，转换为 Delta
- [x] 1.6 实现 `extract` — 返回需要 WebView 环境的错误

## 2. 注册提取器

- [x] 2.1 在 `lib/main.dart` 的 `_initClipperRegistry()` 中导入并注册 `ZhihuZhuanlanExtractor`

## 3. 验证

- [x] 3.1 运行 `flutter analyze` 确保无静态分析错误
- [ ] 3.2 使用知乎专栏 URL 进行端到端剪藏测试
