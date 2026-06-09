# 规则模板提取规格

### Requirement: 规则模板 JSON 格式
系统 SHALL 支持通过 JSON 文件声明站点提取规则，每个规则文件定义一个站点的提取逻辑。

#### Scenario: 规则文件基本结构
- **WHEN** 系统加载一个规则模板 JSON 文件
- **THEN** 该文件 SHALL 包含以下字段：`name`（站点名称）、`url`（URL glob 模式）

#### Scenario: 正文提取字段
- **WHEN** 规则文件定义了 `content` 字段
- **THEN** 系统 SHALL 使用该 CSS 选择器定位正文容器元素

#### Scenario: 标题提取字段
- **WHEN** 规则文件定义了 `title` 字段
- **THEN** 系统 SHALL 使用该 CSS 选择器提取标题文本

#### Scenario: 排除规则字段
- **WHEN** 规则文件定义了 `exclude` 数组字段
- **THEN** 系统 SHALL 从正文中移除匹配这些 CSS 选择器的所有元素

#### Scenario: 元数据字段
- **WHEN** 规则文件定义了 `author` 或 `published` 字段
- **THEN** 系统 SHALL 使用对应的 CSS 选择器提取作者或发布日期

### Requirement: URL glob 模式匹配
系统 SHALL 使用 glob 风格通配符匹配规则文件中的 URL 模式。

#### Scenario: 通配符匹配子路径
- **WHEN** 规则的 URL 模式为 `https://juejin.cn/*/article/*`
- **THEN** URL `https://juejin.cn/post/12345/article/abc` SHALL 匹配成功

#### Scenario: 通配符匹配子域名
- **WHEN** 规则的 URL 模式为 `*.zhihu.com`
- **THEN** URL `https://zhuanlan.zhihu.com/p/12345` SHALL 匹配成功

#### Scenario: 精确匹配
- **WHEN** 规则的 URL 模式不包含通配符
- **THEN** 仅完全匹配的 URL SHALL 匹配成功

### Requirement: 规则文件加载
系统 SHALL 在应用启动时从 `assets/clipper_rules/` 目录加载所有 JSON 规则文件。

#### Scenario: 启动时加载规则
- **WHEN** 应用启动并初始化剪藏模块
- **THEN** 系统 SHALL 读取 `assets/clipper_rules/` 下所有 `.json` 文件，解析为规则模板

#### Scenario: 无效规则文件
- **WHEN** 某个规则文件 JSON 格式错误或缺少必需字段
- **THEN** 系统 SHALL 跳过该规则文件并记录警告日志，不影响其他规则的加载

#### Scenario: 无规则文件
- **WHEN** `assets/clipper_rules/` 目录为空或不存在
- **THEN** 系统 SHALL 正常运行，仅使用专用提取器和 Readability 兜底

### Requirement: 模板提取器执行
系统 SHALL 为每个规则模板创建 `TemplateExtractor` 实例，执行 CSS 选择器提取逻辑。

#### Scenario: CSS 选择器提取正文
- **WHEN** TemplateExtractor 对 HTML 执行提取
- **THEN** 系统 SHALL 使用规则的 `content` 选择器定位正文元素，移除 `exclude` 匹配的噪声元素

#### Scenario: 提取结果转换
- **WHEN** 正文元素提取成功
- **THEN** 系统 SHALL 使用 `convertHtmlToDelta()` 将正文 HTML 转换为 Quill Delta

#### Scenario: 元数据补全
- **WHEN** 规则定义了 `title`/`author`/`published` 选择器
- **THEN** 系统 SHALL 提取对应值填入 `ClipMetadata`

#### Scenario: 选择器无匹配
- **WHEN** 规则的 `content` 选择器在 HTML 中无匹配元素
- **THEN** 系统 SHALL 回退到 Readability 通用提取
