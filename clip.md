# 网页剪藏系统 — 业务逻辑文档

## 概览

剪藏系统采用三层提取架构，支持从任意网页提取正文内容并保存为富文本笔记。

```
用户输入 URL
  ↓
ExtractorRegistry 匹配提取器（按优先级排序）
  ↓
三层提取：专用提取器 → 规则模板 → Readability 兜底
  ↓
HTML → Quill Delta 转换
  ↓
保存为新笔记
```

## 三层提取架构

按优先级从高到低依次尝试，第一个成功即返回：

| 层级 | 优先级 | 提取器 | 说明 |
|------|--------|--------|------|
| 第一层 | 10 | 专用提取器 | 知乎、小红书等需要 WebView 拦截 JS 的站点 |
| 第二层 | 100 | 模板提取器 | JSON 规则文件，CSS 选择器匹配 |
| 第三层 | 9999 | Readability 提取器 | 通用兜底，Mozilla Readability 算法 |

## 剪藏主流程

入口：富文本编辑器工具栏的"剪藏网页"按钮（LucideIcons.link2）

```
_clipWebPage()
  ├── 弹出 WebClipperDialog 输入 URL
  │
  ├── registry.matchWebView(url)
  │   ├── 匹配成功 → ExtractorWebViewPage（专用 WebView 提取）
  │   └── 未匹配 ↓
  │
  ├── registry.extractViaHttp(url)（HTTP 提取）
  │   ├── TemplateExtractor 规则匹配 → CSS 选择器提取
  │   ├── ReadabilityExtractor 兜底 → reader_mode 解析
  │   ├── 成功 → 返回 ClipResult
  │   └── 失败 ↓
  │
  ├── 非 Web 平台 → ReadabilityWebViewPage（WebView 降级）
  │   └── 浏览器加载完整页面 → 延迟 3s 等 JS 渲染 → 提取 HTML
  │
  └── ClipResult.isSuccess?
      ├── 成功 → onClipToNewNote(deltaJson) 创建新笔记
      └── 失败 → 显示错误 SnackBar
```

## 提取器详解

### BaseExtractor 基类

所有提取器的抽象基类（`lib/services/clipper/base_extractor.dart`）：

```dart
abstract class BaseExtractor {
  bool canExtract(Uri url);           // URL 是否匹配
  Future<ClipResult> extract(ExtractContext context);  // 执行提取
  int get priority;                    // 优先级，越小越优先
  bool get requiresWebView => false;   // 是否需要 WebView
}
```

### WebViewExtractor Mixin

需要 WebView 的提取器混入此 mixin（`lib/services/clipper/webview_extractor_mixin.dart`）：

```dart
mixin WebViewExtractor on BaseExtractor {
  bool get requiresWebView => true;
  String get injectedScript;           // 注入页面的 JS 脚本
  String get handlerName;              // JS→Dart 回调通道名
  ClipResult parseResponse(String data, {String? url});  // 解析 JS 返回数据
}
```

### 知乎提取器

`lib/services/clipper/extractors/zhihu_extractor.dart`（priority=10）

- **匹配规则**：`zhihu.com` 且路径包含 `question`，排除 `zhuanlan.zhihu.com`
- **提取方式**：在 `AT_DOCUMENT_START` 注入 JS，拦截 XHR/fetch 请求，捕获 `/api/v4/questions/{id}/feeds` API 响应
- **解析逻辑**：从 Feeds API JSON 中找到目标回答，提取回答 HTML，转 Delta
- **超时**：加载 15s + 捕获 10s

### 小红书提取器

`lib/services/clipper/extractors/xhs_extractor.dart`（priority=10）

- **匹配规则**：`xiaohongshu.com`
- **提取方式**：在 `AT_DOCUMENT_END` 注入 JS，读取 `og:title`、`description`、`og:image` 等 meta 标签
- **特殊处理**：通过 `onTitleChanged` 重新注入脚本（SSR 页面需要等标题变化后才触发）
- **格式化**：话题标签 `#xxx#` 转换，标题去掉" - 小红书"后缀

### 模板提取器

`lib/services/clipper/template_extractor.dart`（priority=100）

基于 JSON 规则文件，用 CSS 选择器提取内容。提取流程：

1. `UrlMatcher.matches(rule.urlPattern, url)` 匹配 URL
2. HTTP 获取页面 HTML
3. CSS 选择器 `rule.title` 提取标题
4. CSS 选择器 `rule.content` 提取正文
5. 移除 `rule.exclude` 中的排除元素
6. `removeNoise` + `convertHtmlToDelta` 转 Delta

### Readability 提取器

`lib/services/clipper/readability_extractor.dart`（priority=9999）

通用兜底，使用 `reader_mode` 包（Mozilla Readability 的 Dart 移植）：

1. `canExtract()` 始终返回 `true`
2. `parse(html)` 解析 HTML，提取正文 `article.content`
3. 补充 og: meta 标签的元数据（author、siteName、coverImage 等）
4. `removeNoise` + `convertHtmlToDelta` 转 Delta

## ExtractorRegistry 注册中心

`lib/services/clipper/extractor_registry.dart` — 单例模式

### 核心方法

| 方法 | 说明 |
|------|------|
| `register(extractor)` | 注册提取器 |
| `match(url)` | 返回最佳匹配（priority 最小） |
| `matchWebView(url)` | 仅筛选 `requiresWebView=true` 的提取器 |
| `extractViaHttp(url)` | 按优先级遍历非 WebView 提取器，HTTP 获取 HTML 后依次尝试 |

### 匹配流程

```
_findCandidates(url, requireWebView)
  → 过滤：platform 匹配（Web 平台跳过 WebView 提取器）
  → 过滤：canExtract(url) == true
  → 排序：priority 升序
  → 返回候选列表
```

## WebView 页面

### ExtractorWebViewPage — 专用提取器 WebView

`lib/widgets/extractor_webview_page.dart`

- 接收 `BaseExtractor` 参数，转型为 `WebViewExtractor`
- 注入时机智能判断：脚本包含 `prototype.open` → `AT_DOCUMENT_START`（拦截 XHR），否则 `AT_DOCUMENT_END`
- 超时策略：加载 15s + 捕获 10s
- 小红书特殊：`onTitleChanged` 时重新注入脚本

### ReadabilityWebViewPage — 通用 WebView 降级

`lib/widgets/clipper_webview_page.dart`

- HTTP 提取失败后的降级方案（Bilibili 等 JS 重度渲染页面）
- `onLoadStop` 后延迟 3 秒，等待 JS 渲染完成
- 注入通用脚本获取 `document.title` + `document.body.innerHTML`
- 拿到 HTML 后 Dart 端做 `removeNoise` + `convertHtmlToDelta`
- 超时 30 秒
- 加载遮罩全程覆盖，用户不会看到裸露的 WebView

## HTML 处理链

`lib/services/web_clipper_service.dart`

### removeNoise

移除噪声元素：
- 脚本样式：`script`, `style`, `noscript`, `iframe`, `svg`
- 页面结构：`nav`, `header`, `footer`
- 广告/评论/侧边栏/分享/推荐/工具栏等

### convertHtmlToDelta

HTML DOM → Quill Delta 转换映射：

| HTML 标签 | Delta 属性 |
|-----------|-----------|
| h1 | `\n{header: 1}` |
| h2 | `\n{header: 2}` |
| h3/h4 | `\n{header: 3}` |
| p | `\n` |
| blockquote | `\n{blockquote: true}` |
| pre > code | `{code-block: true}` |
| ul > li | `\n{list: bullet}` |
| ol > li | `\n{list: ordered}` |
| img | `{image: src}` |
| strong/b | `{bold: true}` |
| em/i | `{italic: true}` |
| u | `{underline: true}` |
| s/del | `{strike: true}` |
| code | `{code: true}` |
| a | `{link: href}` |

### cleanDelta

后处理：合并连续空行为单个换行。

## 数据模型

### ClipResult

```dart
class ClipResult {
  final Delta? delta;          // 成功时的 Quill Delta
  final String? error;         // 失败时的错误信息
  final ClipMetadata? metadata; // 元数据
  bool get isSuccess => delta != null;
}
```

### ClipMetadata

```dart
class ClipMetadata {
  final String? title;       // 标题
  final String? author;      // 作者
  final String? siteName;    // 站点名
  final String? description; // 描述
  final String? coverImage;  // 封面图
  final String? published;   // 发布时间
  final String? favicon;     // 网站图标
}
```

### ExtractContext

```dart
class ExtractContext {
  final String url;
  final String? html;                           // HTTP 获取的 HTML
  final bool isWebPlatform;                     // 是否 Web 平台
  final InAppWebViewController? webViewController; // WebView 控制器
}
```

## JSON 规则文件格式

目录：`assets/clipper_rules/`

```json
{
  "name": "站点名称",
  "url": "URL glob 匹配模式",
  "title": "标题 CSS 选择器",
  "content": "正文 CSS 选择器",
  "exclude": ["需要移除的元素选择器"],
  "author": "作者选择器（可选）",
  "published": "发布时间选择器（可选）"
}
```

URL glob 模式：`*` 匹配不含 `/` 的字符，`**` 匹配任意字符。

### 现有规则

| 文件 | 站点 | URL 模式 | 正文选择器 |
|------|------|---------|-----------|
| `juejin.json` | 掘金 | `https://juejin.cn/post/*` | `div.article-content` |
| `yuque.json` | 语雀 | `https://www.yuque.com/*/*/*` | `div.yuque-doc-content` |

## 初始化

`lib/main.dart` 的 `main()` → `_initClipperRegistry()` 按顺序注册：

```
ZhihuExtractor()           — priority=10, requiresWebView=true
XhsExtractor()             — priority=10, requiresWebView=true
TemplateExtractor(rules)   — priority=100, 从 assets/clipper_rules/ 加载
ReadabilityExtractor()     — priority=9999
```

注册顺序不影响匹配结果，`_findCandidates` 始终按 `priority` 排序。

## 保存流程

剪藏成功后通过 `onClipToNewNote(deltaJson)` 回调将 Delta JSON 传出。

### 桌面端（HomeScreen 标签页模式）

`lib/screens/home_screen.dart` — `_clipToNewNote()`

1. `_extractTitle(deltaJson)` 从 Delta 提取第一个非空行作为标题（≤50 字符）
2. 创建 `Note` 对象（id = 毫秒时间戳）
3. `storageService.saveNote(note)` 保存
4. `_loadNotes()` 刷新笔记列表
5. `_openTab(note)` 在新标签页打开

### 移动端（EditorScreen 单页模式）

`lib/screens/editor_screen.dart` — 内联回调

1. 同样 `_extractTitle(deltaJson)` 提取标题
2. 创建 `Note` 对象
3. `storageService.saveNote(note)` 保存
4. `Navigator.pushReplacement` 跳转到新编辑页面（替换当前页面）

## 文件清单

| 文件 | 作用 |
|------|------|
| `lib/main.dart` | 提取器注册入口 |
| `lib/widgets/rich_text_editor.dart` | 剪藏按钮 + `_clipWebPage()` 主流程 |
| `lib/widgets/web_clipper_dialog.dart` | URL 输入对话框 |
| `lib/widgets/extractor_webview_page.dart` | 专用提取器 WebView 页面 |
| `lib/widgets/clipper_webview_page.dart` | Readability 通用 WebView 降级页面 |
| `lib/services/web_clipper_service.dart` | HTML 处理工具（removeNoise/convertHtmlToDelta/cleanDelta） |
| `lib/services/clipper/base_extractor.dart` | 提取器抽象基类 |
| `lib/services/clipper/webview_extractor_mixin.dart` | WebView 提取器 mixin |
| `lib/services/clipper/extractor_registry.dart` | 提取器注册中心（单例） |
| `lib/services/clipper/extract_context.dart` | 提取器上下文 |
| `lib/services/clipper/clip_result.dart` | ClipResult + ClipMetadata |
| `lib/services/clipper/extractors/zhihu_extractor.dart` | 知乎提取器 |
| `lib/services/clipper/extractors/xhs_extractor.dart` | 小红书提取器 |
| `lib/services/clipper/template_extractor.dart` | JSON 规则模板提取器 |
| `lib/services/clipper/template_rule.dart` | ClipperRule 模型 + RuleLoader |
| `lib/services/clipper/url_matcher.dart` | URL glob 匹配 |
| `lib/services/clipper/readability_extractor.dart` | Readability 通用兜底 |
| `lib/screens/home_screen.dart` | 桌面端保存逻辑 |
| `lib/screens/editor_screen.dart` | 移动端保存逻辑 |
| `assets/clipper_rules/*.json` | 模板规则文件 |

## 扩展新站点

### 方式一：添加 JSON 规则（推荐，无需写代码）

在 `assets/clipper_rules/` 下新建 JSON 文件：

```json
{
  "name": "example.com",
  "url": "https://example.com/articles/*",
  "title": "h1",
  "content": "div.article-body",
  "exclude": ["script", ".ad-banner"]
}
```

适用于：静态 HTML 页面，有明确的 CSS 选择器可以定位正文。

### 方式二：添加专用提取器

适用于需要 WebView 拦截 JS API 的站点（如知乎拦截 Feeds API）。

1. 在 `lib/services/clipper/extractors/` 下新建提取器类
2. `extends BaseExtractor with WebViewExtractor`
3. 实现 `canExtract`、`injectedScript`、`handlerName`、`parseResponse`
4. 在 `main.dart` 的 `_initClipperRegistry()` 中注册
