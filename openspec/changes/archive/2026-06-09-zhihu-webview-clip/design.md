## Context

项目已有三层剪藏架构：专用提取器 → 规则模板提取器 → Readability 兜底。`ZhihuExtractor` 处理知乎问答 (`zhihu.com/question/`)，但明确排除了专栏域名 `zhuanlan.zhihu.com`。知乎专栏文章的页面结构完全不同于问答——正文内容嵌入在 `<script id="js-initialData" type="text/json">` 标签的 JSON 数据中，通用提取器无法正确获取。

现有 `WebViewExtractorMixin` 提供了标准化的 JS 注入 + 回调模式，新提取器可复用此基础设施。

## Goals / Non-Goals

**Goals:**
- 支持 `zhuanlan.zhihu.com/p/{id}` URL 的剪藏
- 从 `<title/>` 提取标题，从 `js-initialData` JSON 中提取正文 HTML
- HTML 正文正确转换为 Quill Delta 格式
- 遵循现有提取器架构模式（WebViewExtractor mixin）

**Non-Goals:**
- 不处理知乎问答页面（已有 ZhihuExtractor）
- 不处理知乎专栏的评论、点赞等附属内容
- 不修改现有提取器接口或注册中心机制

## Decisions

### D1: 新建独立提取器而非修改现有 ZhihuExtractor

**选择**: 创建 `ZhihuZhuanlanExtractor` 独立类

**理由**: 知乎问答和专栏的页面结构、数据来源完全不同。问答拦截 API feeds，专栏从 HTML 中解析 JSON 数据。强行合并会增加单个类的复杂度，违反单一职责。现有 `ZhihuExtractor` 的 `canExtract` 已排除 `zhuanlan.zhihu.com`，两个提取器可独立工作。

**备选方案**: 在 ZhihuExtractor 中增加条件分支 — 拒绝，因为两种页面提取逻辑差异过大。

### D2: WebView 拦截方式 — 页面加载完成后提取 HTML

**选择**: 使用 `AT_DOCUMENT_END` 时机注入 JS，直接从 DOM 提取 `<script id="js-initialData">` 内容

**理由**: 知乎专栏的正文数据在初始 HTML 的 `<script>` 标签中，页面加载完成后即可获取，无需等待额外 API 请求。这比拦截网络请求更简单可靠。

### D3: JSON 解析路径

**选择**: 解析路径 `initialState.entities.articles.{articleId}.content`

**实现**: articleId 从 URL 路径 `/p/{id}` 中提取。使用 `dart:convert` 的 `jsonDecode` 解析 JSON。

### D4: Delta 构建格式

**选择**: 与 ZhihuExtractor 一致的格式 — 标题作为 h1，URL 链接，正文内容

**理由**: 保持知乎内容在笔记中的一致展示风格。

### D5: 优先级设为 10

**选择**: `priority => 10`，与 ZhihuExtractor 同级

**理由**: 同为专用提取器，应在规则模板和 Readability 之前匹配。

## Risks / Trade-offs

- **[JS-initialData 不存在]** → 降级到 Readability 提取器处理（注册中心自动降级机制）
- **[JSON 结构变化]** → parseResponse 中做防御性解析，字段缺失时返回有意义的错误信息
- **[专栏文章内容为富文本 HTML]** → 复用现有 `WebClipperService.convertHtmlToDelta` 进行转换
