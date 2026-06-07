## Context

当前剪藏功能的三个提取策略（通用 HTTP + CSS 选择器、知乎 HTTP + API、WebView + JS 注入）通过硬编码 if/else 路由，每新增站点需要创建独立的 Service + WebViewPage 并在两处添加路由分支。共享工具（`removeNoise`、`convertHtmlToDelta`、`ClipResult`）集中在 `WebClipperService` 上作为静态方法，各服务直接依赖这个大类。

关键约束：
- WebView 提取仅限 Android/Windows（`flutter_inappwebview` 不支持 Web 平台）
- XHS 页面为 JS 渲染，内容在 meta 标签而非 DOM body
- 知乎有双策略（WebView 拦截 API / HTTP 直接调用），需共存
- 最终产物始终是 `ClipResult`（含 `Delta?`），通过 `Navigator.pop` 回传

## Goals / Non-Goals

**Goals:**
- 新增站点支持时，只需添加一个提取器类或一个 JSON 规则文件，不改动路由和框架代码
- 提供通用元数据提取能力（标题、作者、日期、站点名、封面图），减少每个站点提取器的重复逻辑
- 支持声明式规则模板，对结构化内容站点（掘金、语雀等）零代码适配
- 将现有知乎/小红书服务平滑重构为提取器实现

**Non-Goals:**
- 不实现 Obsidian Clipper 的完整 Defuddle 通用引擎（提取引擎功能范围限定在 meta + CSS 选择器 + DOM 遍历）
- 不支持用户在应用内编辑规则模板（规则文件随应用打包，后续可扩展）
- 不改造 `convertHtmlToDelta` 的转换逻辑（保持现有 HTML → Delta 转换不变）
- 不改变剪藏结果的存储方式（仍然是 Note.content 中的 Delta JSON 字符串）

## Decisions

### D1: 提取器接口设计

**决定**：采用抽象类 + 工厂注册模式，而非接口 + 依赖注入。

```
BaseExtractor (abstract)
├── canExtract(Uri url) → bool       // URL 是否匹配
├── extract(context) → Future<ClipResult>  // 执行提取
├── priority → int                   // 优先级（数字越小越优先）
└── requiresWebView → bool           // 是否需要 WebView 环境
```

**理由**：
- `requiresWebView` 让注册中心在 Web 平台自动跳过 WebView 提取器，无需平台判断散落各处
- `priority` 解决多提取器匹配同一 URL 时的选择问题（专用提取器优先于通用提取器）
- 工厂注册（`ExtractorRegistry.register()`）比反射/代码生成更简单可控

**备选方案**：纯接口（`abstract interface class`）+ 外部工厂 — 更解耦但增加文件数和复杂度，对当前项目规模不值得。

### D2: URL 模式匹配策略

**决定**：使用 glob 风格通配符匹配 URL，而非正则表达式。

```
// 规则中的 URL 模式
"*.zhihu.com"              → 匹配 zhihu.com 所有子域
"zhihu.com/question/*"     → 匹配知乎问答
"juejin.cn/book/*/section/*" → 匹配掘金小册章节
```

**理由**：
- Glob 模式更直观，与简悦的 URL 配置格式一致
- Dart 生态有 `glob` 包可直接使用
- 正则对 URL 匹配过于强大，易写出难以调试的模式

**备选方案**：正则表达式 — 更灵活但配置门槛高，不利于规则模板的易用性。可在 `canExtract` 中对需要精确匹配的提取器局部使用正则。

### D3: 规则模板格式

**决定**：采用类简悦 JSON 格式，每个规则文件一个 JSON 对象，应用启动时从 assets 加载。

```json
{
  "name": "juejin.cn",
  "url": "https://juejin.cn/*/article/*",
  "title": "h1.article-title",
  "content": "div.markdown-body",
  "exclude": ["div.author-block", ".ad-container"],
  "author": "meta[name=author]",
  "published": "time[datetime]"
}
```

**字段说明**：
- `url`：glob 模式，匹配则应用此规则
- `title`/`content`：CSS 选择器，定位标题和正文容器
- `exclude`：CSS 选择器列表，从正文中移除噪声元素
- `author`/`published`：可选，元数据 CSS 选择器
- 缺省字段使用通用元数据提取器兜底

**理由**：
- 一个 JSON 文件就能适配一个新站点，零 Dart 代码
- CSS 选择器已是 Web 开发通用技能，规则编写门槛低
- JSON 可直接放在 `assets/clipper_rules/` 下，随应用打包

**备选方案**：YAML 格式 — 更适合手写但需要额外依赖解析包；Dart 代码配置 — 灵活但失去声明式优势。

### D4: 正文提取算法 — 引入 Readability

**决定**：通用兜底层引入 `reader_mode` 包（Mozilla Readability.js 的纯 Dart 移植），替代当前硬编码的 `_contentSelectors` CSS 选择器列表。

```dart
import 'package:reader_mode/reader_mode.dart';

// Readability 自动提取：标题、正文 HTML、作者、站点名、发布时间、语言
final article = parse(html, baseUri: url);
// article.title, article.content (清理后 HTML), article.byline,
// article.siteName, article.publishedTime, article.lang
```

**选择 Readability 的依据**（参考 [Bevendorff et al. 2023](https://downloads.webis.de/publications/papers/bevendorff_2023c.pdf) 学术评测）：
- 14 个提取器中，Readability **中位 F1 最高（0.970）**，稳定性最好
- 启发式算法无需站点配置，开箱即用
- `reader_mode` 是纯 Dart 实现，**全平台支持**（Android/iOS/Web/Windows/macOS/Linux）
- 仅依赖 `html` 包（项目已有），无原生依赖，无平台限制

**备选方案对比**：

| 方案 | F1 (均值/中位) | Dart 可用性 | 适用范围 |
|------|---------------|------------|---------|
| **Readability** (`reader_mode`) | 0.861 / **0.970** | 纯 Dart，全平台 | 通用文章 |
| Trafilatura | **0.883** / 0.957 | 无 Dart 包（Python） | 需服务端 |
| CSS 选择器列表 (当前) | 未知，依赖人工维护 | 已有 | 已知站点 |
| Dragnet | 0.823 / 0.943 | 无 Dart 包（Python） | 学术研究 |

**为什么同时保留规则模板**：Readability 擅长通用文章提取，但对特定站点结构（如掘金的代码块、语雀的嵌套列表）可能丢失格式。规则模板通过 CSS 选择器精确定位，补充 Readability 的不足。

### D5: 三层提取架构（修订版）

**决定**：三层降级架构，通用兜底层从 CSS 选择器列表升级为 Readability 算法。

```
输入 URL
    │
    ▼
ExtractorRegistry.match(url)
    │
    ├─ 第1层：站点专用提取器（ZhihuExtractor, XhsExtractor 等）
    │   └─ 处理需要 WebView/JS 注入/API 拦截的复杂站点
    │
    ├─ 第2层：规则模板（TemplateRule）
    │   ├─ CSS 选择器精确提取正文
    │   └─ MetadataExtractor 补全缺失元数据
    │
    └─ 第3层：Readability 通用兜底
        ├─ reader_mode 自动提取正文 + 元数据
        └─ 替代原 _contentSelectors 硬编码列表
```

**层次说明**：
1. **专用提取器层**：优先匹配，处理需要 JS 注入或 API 拦截的复杂站点
2. **规则模板层**：CSS 选择器提取，精确覆盖已知结构的内容站点
3. **Readability 兜底层**：启发式算法自动提取，零配置覆盖任意网页

### D6: ClipResult 模型扩展

**决定**：扩展 `ClipResult` 增加可选元数据字段，保持向后兼容。

```dart
class ClipMetadata {
  final String? title;
  final String? author;
  final String? siteName;
  final String? description;
  final String? coverImage;
  final String? published;
  final String? favicon;
}

class ClipResult {
  final Delta? delta;
  final String? error;
  final ClipMetadata? metadata;  // 新增，可选
  bool get isSuccess => delta != null;
}
```

**理由**：
- `ClipMetadata` 作为可选字段，现有代码无需修改即可编译
- 元数据可用于未来功能（笔记标题自动填充、来源信息展示等）
- 不影响已存储的 Note 数据（`content` 字段仅存 Delta JSON）

### D7: WebView 提取页统一

**决定**：创建通用 `ClipperWebViewPage`，接受提取器实例而非硬编码站点逻辑。

```dart
class ClipperWebViewPage extends StatefulWidget {
  final BaseExtractor extractor;
  final String url;
  // ...
}
```

提取器通过 `WebViewExtractor` mixin 提供 JS 脚本和结果解析方法：
```dart
mixin WebViewExtractor on BaseExtractor {
  String get injectedScript;       // 要注入的 JS
  String get handlerName;          // Flutter 端回调名称
  ClipResult parseResponse(String data);  // 解析 JS 回传数据
}
```

**理由**：当前 `ZhihuWebViewPage` 和 `XhsWebViewPage` 的骨架几乎相同（加载、注入、超时、pop 结果），仅 JS 脚本和解析逻辑不同。统一为通用页面后，新 WebView 提取器只需提供 JS 脚本和解析器。

### D8: 目录结构

```
lib/services/clipper/
├── extractor_registry.dart      # 注册中心
├── base_extractor.dart          # 抽象基类
├── clip_result.dart             # ClipResult + ClipMetadata
├── metadata_extractor.dart      # 通用元数据提取（meta/og/Schema.org 降级）
├── readability_extractor.dart   # Readability 通用兜底提取器（reader_mode）
├── template_rule.dart           # 规则模板解析器
├── template_extractor.dart      # 基于模板的提取器
├── extractors/
│   ├── zhihu_extractor.dart     # 知乎（重构自 ZhihuWebViewService）
│   └── xhs_extractor.dart       # 小红书（重构自 XhsWebViewService）
└── webview_extractor_mixin.dart # WebView 提取 mixin

lib/widgets/
├── clipper_webview_page.dart    # 通用 WebView 提取页（替代两个专用页）

assets/clipper_rules/
├── juejin.json                  # 掘金规则
├── yuque.json                   # 语雀规则
└── ...                          # 更多规则文件
```

**理由**：
- `clipper/` 子目录隔离剪藏相关代码，避免 `services/` 目录膨胀
- `extractors/` 子目录按站点组织提取器实现
- 规则文件在 assets 中，应用启动时加载

## Risks / Trade-offs

**[R1] 规则模板的表达力有限** → 复杂站点（如 Notion 的动态渲染、Twitter 的线程）无法用 CSS 选择器覆盖，仍需编写 Dart 提取器。但规则模板的目标是覆盖 80% 的结构化内容站点，复杂站点走专用提取器路径。

**[R2] 重构期间可能引入回归** → 采用增量重构：先建立新架构（注册中心 + 基类 + Readability 提取器），验证通用路径可用后，再逐个迁移知乎/小红书。每步迁移后手动验证对应站点的剪藏功能。

**[R3] `reader_mode` 包刚发布（0.2.0），稳定性存疑** → 该包是 Mozilla Readability.js 的完整移植，Readability 算法本身已稳定运行 10+ 年，被 Firefox/Safari 阅读模式广泛使用。包的依赖仅 `html`（项目已有），且纯 Dart 实现，可自行 fork 维护。若出现问题，可回退到现有 `_contentSelectors` 逻辑。

**[R4] glob 包增加依赖** → `glob` 是 Dart 团队官方维护的包，体积小（~30KB），无原生依赖，风险极低。若不愿引入，可用 `String` 通配符匹配作为降级方案。

**[R5] 通用 WebView 页可能无法覆盖所有 JS 注入模式** → 通过 `WebViewExtractor` mixin 的 `injectedScript`/`handlerName`/`parseResponse` 提供足够灵活性。若后续出现更复杂的注入需求（如多阶段脚本），可在 mixin 中扩展 `onLoadStop` 等回调。

## Migration Plan

1. **Phase 1 - 基础架构 + Readability**：创建 `clipper/` 目录，引入 `reader_mode` 包，实现 `ClipResult`+`ClipMetadata`、`BaseExtractor`、`ExtractorRegistry`、`ReadabilityExtractor`（通用兜底）。验证：通用网页剪藏使用 Readability 提取效果
2. **Phase 2 - 规则模板**：实现 `TemplateRule` 解析器和 `TemplateExtractor`，添加首批规则文件。验证：规则模板站点提取效果
3. **Phase 3 - WebView 统一**：创建 `ClipperWebViewPage` + `WebViewExtractor` mixin，实现 `ZhihuExtractor` 和 `XhsExtractor`。验证：知乎/小红书剪藏功能
4. **Phase 4 - 路由切换**：将 `_clipWebPage` 中的 if/else 改为 `ExtractorRegistry.match(url).extract()`，删除旧的专用 WebView Page 和 Service 类
5. **Phase 5 - 清理**：删除 `web_clipper_service.dart` 中已迁移的代码，保留 `convertHtmlToDelta`/`removeNoise` 为共享工具方法

每阶段完成后手动验证：Readability 通用 → 规则模板站点 → 知乎 → 小红书。

## Open Questions

- `reader_mode` 0.2.0 刚发布，需验证对中文网页的提取质量（知乎专栏、微信公众号等）。若效果不佳，是否需要预处理 HTML（如补充 meta 标签）再传入 Readability？
- 规则模板是否需要支持 `include` 字段的嵌套选择器（类似简悦的 `[[{(()=>{...})()}]]` JS 表达式）？初始版本建议仅支持 CSS 选择器。
- 提取的元数据（author、published 等）是否需要在笔记模型中持久化存储？当前 Note 模型无这些字段，可作为后续需求。
- `MetadataExtractor` 的多源降级策略（meta → Schema.org → DOM）是否仍需实现，还是 Readability 的 `article.byline`/`article.publishedTime` 已足够覆盖？
