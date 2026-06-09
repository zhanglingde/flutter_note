## Why

现有 `ZhihuExtractor` 仅处理知乎问答页面 (`zhihu.com/question/`)，明确排除了知乎专栏 (`zhuanlan.zhihu.com/p/{id}`)。专栏文章的页面结构与问答完全不同，内容嵌在 `<script id="js-initialData">` 的 JSON 数据中，通用 Readability 提取器无法正确获取结构化内容。需要新增专用提取器来支持知乎专栏文章的剪藏。

## What Changes

- 新增 `ZhihuZhuanlanExtractor`，匹配 `zhuanlan.zhihu.com/p/{id}` URL 模式
- 通过 WebView 拦截页面 HTML，从 `<title/>` 提取标题，从 `<script id="js-initialData" type="text/json">` 的 JSON 中提取正文内容（路径：`initialState.entities.articles.{id}.content`）
- 将 HTML 正文转换为 Quill Delta 格式
- 在 `main.dart` 注册新提取器

## Capabilities

### New Capabilities
- `zhihu-zhuanlan-clip`: 知乎专栏文章的 WebView 拦截剪藏能力，包括 URL 匹配、HTML 拦截、JSON 数据提取、Delta 转换

### Modified Capabilities

（无现有规格需要修改）

## Impact

- **新增文件**: `lib/services/clipper/extractors/zhihu_zhuanlan_extractor.dart`
- **修改文件**: `lib/main.dart`（注册新提取器）
- **依赖**: 现有 `WebViewExtractorMixin`、`WebClipperService`、`ExtractContext`、`ClipResult` 基础设施
