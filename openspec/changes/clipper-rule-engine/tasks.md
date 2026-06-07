## 1. 基础架构与数据模型

- [x] 1.1 创建 `lib/services/clipper/` 目录结构，添加 `reader_mode` 和 `glob` 依赖到 pubspec.yaml
- [x] 1.2 实现 `ClipMetadata` 数据类（title/author/siteName/description/coverImage/published/favicon，全部可选）
- [x] 1.3 扩展 `ClipResult` 类，增加可选 `metadata` 字段，保持向后兼容（现有 `ClipResult.success(delta)` 构造不受影响）
- [x] 1.4 实现 `ExtractContext` 类（包含 url、html、isWebPlatform、可选 WebView 控制器引用）
- [x] 1.5 实现 `BaseExtractor` 抽象类（canExtract、extract、priority、requiresWebView）

## 2. 注册中心

- [x] 2.1 实现 `ExtractorRegistry` 类（register、match 方法，支持 priority 排序和 requiresWebView 平台过滤）
- [x] 2.2 实现 match 方法的降级逻辑：专用提取器 → 规则模板 → Readability 兜底
- [x] 2.3 实现提取执行入口方法（HTTP 获取 HTML → 构造 ExtractContext → 调用 extract）
- [x] 2.4 实现提取失败时的自动降级到下一个候选提取器

## 3. Readability 通用兜底提取器

- [x] 3.1 实现 `ReadabilityExtractor`（priority 设为最低，canExtract 始终返回 true）
- [x] 3.2 集成 `reader_mode` 包：HTTP 获取 HTML → `parse()` 提取正文 → 获取元数据
- [x] 3.3 将 Readability 返回的 HTML 正文通过 `convertHtmlToDelta()` 转换为 Quill Delta
- [x] 3.4 实现 meta 标签元数据补全（og:description、og:image 等补充 Readability 未返回的字段）
- [x] 3.5 处理 `isProbablyReaderable` 返回 false 的情况，返回 ClipResult.failure

## 4. 规则模板系统

- [x] 4.1 定义规则模板 JSON 数据模型（ClipperRule：name、url、title、content、exclude、author、published）
- [x] 4.2 实现 `TemplateRule` 解析器，从 JSON 文件加载并解析规则
- [x] 4.3 实现 glob URL 模式匹配（使用 `glob` 包或 String 通配符匹配）
- [x] 4.4 实现 `TemplateExtractor`（基于规则的 CSS 选择器提取正文、移除 exclude 元素、提取元数据）
- [x] 4.5 实现规则文件加载：启动时从 `assets/clipper_rules/` 读取所有 JSON 文件并注册
- [x] 4.6 处理无效规则文件（JSON 格式错误跳过并警告）
- [x] 4.7 添加首批规则模板文件（掘金 juejin.json、语雀 yuque.json）

## 5. WebView 提取统一

- [x] 5.1 实现 `WebViewExtractor` mixin（injectedScript、handlerName、parseResponse）
- [x] 5.2 实现通用 `ClipperWebViewPage`（接受 BaseExtractor，注入 JS 脚本，处理回调，超时控制，Navigator.pop 返回 ClipResult）
- [x] 5.3 实现 `ZhihuExtractor`（重构自 ZhihuWebViewService）：canExtract 匹配知乎问答 URL，注入 Feeds API 拦截脚本，parseResponse 解析 JSON 响应
- [x] 5.4 实现 `XhsExtractor`（重构自 XhsWebViewService）：canExtract 匹配小红书 URL，注入 meta 标签提取脚本，parseResponse 解析提取数据

## 6. 路由迁移与清理

- [x] 6.1 重构 `_clipWebPage`（rich_text_editor.dart）：将 if/else 链替换为 `ExtractorRegistry.match(url)` 路由
- [x] 6.2 WebView 提取路径：匹配到 requiresWebView 提取器时，使用 `ClipperWebViewPage` 加载并获取结果
- [x] 6.3 HTTP 提取路径：匹配到非 WebView 提取器时，直接通过注册中心执行提取
- [x] 6.4 删除 `zhihu_webview_page.dart` 和 `xhs_webview_page.dart`（已被通用 ClipperWebViewPage 替代）
- [x] 6.5 删除 `zhihu_webview_service.dart` 和 `xhs_webview_service.dart`（已被提取器替代）
- [x] 6.6 清理 `web_clipper_service.dart`：移除已迁移的路由逻辑和 _contentSelectors，保留 `convertHtmlToDelta`/`removeNoise`/`cleanDelta` 为共享工具

## 7. 验证

- [ ] 7.1 手动验证 Readability 通用提取：测试 3-5 个不同类型网页（新闻、博客、文档）
- [ ] 7.2 手动验证规则模板提取：测试掘金/语雀规则文件对应站点
- [ ] 7.3 手动验证知乎剪藏功能（Android/Windows WebView 提取）
- [ ] 7.4 手动验证小红书剪藏功能（Android/Windows WebView 提取）
- [ ] 7.5 验证 Web 平台：知乎/小红书 URL 自动降级到 Readability HTTP 提取
- [ ] 7.6 运行 `flutter analyze` 确保无警告
