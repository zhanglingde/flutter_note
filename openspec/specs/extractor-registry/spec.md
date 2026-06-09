# 提取器注册中心规格

### Requirement: 提取器注册
系统 SHALL 提供 `ExtractorRegistry` 注册中心，支持在应用启动时注册所有可用提取器。

#### Scenario: 注册提取器实例
- **WHEN** 应用初始化时
- **THEN** 注册中心 SHALL 接受 `BaseExtractor` 实例的注册，并存入内部列表

#### Scenario: 注册规则模板提取器
- **WHEN** 应用加载 `assets/clipper_rules/` 下的 JSON 规则文件时
- **THEN** 注册中心 SHALL 为每个规则文件创建 `TemplateExtractor` 实例并注册

#### Scenario: 重复注册
- **WHEN** 同一个提取器被注册多次
- **THEN** 注册中心 SHALL 保留所有注册实例（允许多个提取器匹配同一 URL 模式）

### Requirement: URL 模式匹配
系统 SHALL 根据目标 URL 从已注册提取器中找到最佳匹配。

#### Scenario: 单个提取器匹配
- **WHEN** 用户输入一个 URL，且只有一个提取器的 `canExtract(url)` 返回 true
- **THEN** 注册中心 SHALL 返回该提取器

#### Scenario: 多个提取器匹配
- **WHEN** 多个提取器的 `canExtract(url)` 均返回 true
- **THEN** 注册中心 SHALL 返回 `priority` 值最小的提取器

#### Scenario: 无匹配时使用通用兜底
- **WHEN** 没有专用提取器或规则模板匹配目标 URL
- **THEN** 注册中心 SHALL 返回 Readability 通用提取器作为兜底

### Requirement: 平台感知过滤
系统 SHALL 根据运行平台自动过滤不可用的提取器。

#### Scenario: Web 平台过滤
- **WHEN** 应用运行在 Web 平台（`kIsWeb` 为 true）
- **THEN** 注册中心 SHALL 跳过所有 `requiresWebView` 为 true 的提取器，回退到 HTTP 提取器

#### Scenario: 原生平台
- **WHEN** 应用运行在 Android 或 Windows 平台
- **THEN** 注册中心 SHALL 包含所有已注册的提取器（WebView 和 HTTP）

### Requirement: 提取执行
系统 SHALL 提供统一的提取入口方法，自动处理匹配和执行。

#### Scenario: 同步提取（HTTP）
- **WHEN** URL 匹配到不需要 WebView 的提取器
- **THEN** 注册中心 SHALL 通过 HTTP 获取 HTML，构造 `ExtractContext`，调用提取器的 `extract` 方法

#### Scenario: WebView 提取
- **WHEN** URL 匹配到需要 WebView 的提取器
- **THEN** 注册中心 SHALL 返回提取器实例，由调用方创建 WebView 页面执行提取

#### Scenario: 提取失败降级
- **WHEN** 匹配到的提取器执行失败
- **THEN** 注册中心 SHALL 尝试使用下一个匹配的提取器，若无更多候选则返回失败 ClipResult
