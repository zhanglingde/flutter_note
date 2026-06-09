# 提取器抽象基类规格

### Requirement: 提取器抽象基类
系统 SHALL 提供 `BaseExtractor` 抽象类，定义所有提取器的标准接口协议。

#### Scenario: 定义 canExtract 方法
- **WHEN** 注册中心对 URL 进行匹配时
- **THEN** 提取器 SHALL 通过 `canExtract(Uri url)` 方法返回布尔值表明是否能处理该 URL

#### Scenario: 定义 extract 方法
- **WHEN** 注册中心选中一个提取器执行提取时
- **THEN** 提取器 SHALL 通过 `extract(ExtractContext context)` 异步方法返回 `ClipResult`

#### Scenario: 定义 priority 属性
- **WHEN** 多个提取器匹配同一 URL 时
- **THEN** 注册中心 SHALL 按 `priority` 属性值从小到大选择优先级最高的提取器

#### Scenario: 定义 requiresWebView 属性
- **WHEN** 应用运行在 Web 平台（`kIsWeb` 为 true）时
- **THEN** 注册中心 SHALL 自动跳过 `requiresWebView` 为 true 的提取器

### Requirement: ClipMetadata 元数据模型
系统 SHALL 提供 `ClipMetadata` 数据类，包含可选的网页元数据字段。

#### Scenario: 元数据字段完整性
- **WHEN** 提取器成功提取网页元数据
- **THEN** `ClipMetadata` SHALL 包含以下可选字段：title、author、siteName、description、coverImage、published、favicon

#### Scenario: 元数据字段全部可选
- **WHEN** 提取器无法提取某些元数据
- **THEN** 对应字段 SHALL 为 null，不影响 ClipResult 的成功状态

### Requirement: ClipResult 模型扩展
系统 SHALL 扩展现有 `ClipResult` 类，增加可选的 `ClipMetadata` 字段，保持向后兼容。

#### Scenario: 向后兼容
- **WHEN** 现有代码使用 `ClipResult.success(delta)` 构造（不传 metadata）
- **THEN** `metadata` 字段 SHALL 为 null，现有行为不受影响

#### Scenario: 携带元数据
- **WHEN** 提取器成功提取正文和元数据
- **THEN** `ClipResult` SHALL 可通过 `ClipResult.success(delta, metadata: metadata)` 构造携带元数据

### Requirement: ExtractContext 提取上下文
系统 SHALL 提供 `ExtractContext` 类，封装提取过程所需的上下文信息。

#### Scenario: 上下文包含必要信息
- **WHEN** 注册中心调用提取器的 extract 方法
- **THEN** `ExtractContext` SHALL 包含：目标 URL、HTTP 响应的 HTML 内容（如有）、平台信息（是否为 Web 平台）

#### Scenario: WebView 提取上下文
- **WHEN** 提取器需要 WebView 环境执行提取
- **THEN** `ExtractContext` SHALL 可选包含 WebView 控制器引用，供 WebView 提取器注入 JS 脚本
