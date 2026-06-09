## Why

当前剪藏功能采用硬编码 if/else 链路由 URL 到对应站点服务（知乎、小红书各一个 Service + WebViewPage），每新增一个站点需要创建独立的 Service 类、WebView 页面组件，并在两处路由代码中添加分支。这种模式难以扩展，随着支持站点增多，代码维护成本和出错概率急剧上升。需要一个基于规则注册的提取引擎，让新增站点只需声明规则配置或实现提取器接口，无需改动路由和框架代码。

## What Changes

- 引入**提取器注册中心（Extractor Registry）**：基于 URL 模式匹配，自动路由到对应提取器，替代 if/else 链
- 引入**通用元数据提取器（Metadata Extractor）**：参考 Obsidian Clipper 的 Defuddle 引擎，对标题、作者、发布日期等元数据实现多来源降级策略（meta 标签 → Schema.org → DOM 元素）
- 引入**站点提取器接口（Base Extractor）**：定义 `canExtract(url)` + `extract(html, url)` 标准接口，现有知乎/小红书服务重构为实现该接口的提取器
- 引入**规则模板系统（Template Rules）**：参考简悦的 JSON 模板格式，支持通过声明式配置（URL 模式 + CSS 选择器 + 排除规则）快速适配新站点，无需编写 Dart 代码
- 统一 `ClipResult` 数据模型，增加元数据字段（author、published、site、description、coverImage）
- **BREAKING** 现有 `ZhihuWebViewService`、`XhsWebViewService`、专用 WebView Page 将被重构为提取器实现，调用方需迁移到注册中心 API

## Capabilities

### New Capabilities
- `extractor-registry`: 提取器注册中心 — URL 模式匹配、提取器路由、优先级排序、提取结果标准化
- `metadata-extractor`: 通用元数据提取 — 多来源降级策略（og/meta → Schema.org → DOM）、标题/作者/日期/站点名/描述/封面图提取
- `template-rules`: 规则模板系统 — 声明式 JSON 配置定义站点提取规则（URL 模式、CSS 选择器、排除规则、自定义 CSS），支持热加载规则文件
- `base-extractor`: 提取器基础接口 — `canExtract()`/`extract()` 标准协议、ClipResult 扩展模型（含元数据字段）、提取上下文传递

### Modified Capabilities
- `web-clipper`: 路由逻辑从 if/else 链改为通过注册中心匹配提取器，`WebClipperService` 的 `_contentSelectors` 和 `removeNoise` 合入通用元数据提取器
- `webview-interceptor`: 知乎/小红书的 WebView 拦截逻辑重构为 `ZhihuExtractor`/`XhsExtractor` 实现，WebView 页面统一为通用 WebView 提取页

## Impact

- **核心文件变更**：`web_clipper_service.dart`（路由重构）、`rich_text_editor.dart`（剪藏入口简化）、`zhihu_webview_service.dart` 和 `xhs_webview_service.dart`（重构为提取器）
- **新增文件**：提取器注册中心、元数据提取器、基础接口、规则模板解析器、规则配置 JSON 文件
- **数据模型**：`ClipResult` 扩展元数据字段，需确保向后兼容（已存储的 Note 不受影响）
- **依赖**：可能需要引入 `glob` 或 `pattern` 相关包用于 URL 模式匹配
- **平台兼容**：WebView 提取仍限 Android/Windows，Web 平台继续使用 HTTP 方案
