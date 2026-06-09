## MODIFIED Requirements

### Requirement: 网页正文抓取
系统 SHALL 通过提取器注册中心（ExtractorRegistry）路由目标 URL，自动匹配最佳提取器抓取网页正文内容，并将其转换为 Quill Delta 格式。

#### Scenario: 专用提取器抓取成功
- **WHEN** 用户确认一个有效 URL 且注册中心匹配到专用提取器（如知乎、小红书）
- **THEN** 系统 SHALL 使用该提取器执行抓取，返回 Quill Delta 格式内容

#### Scenario: 规则模板抓取成功
- **WHEN** 用户确认一个有效 URL 且注册中心匹配到规则模板
- **THEN** 系统 SHALL 通过 CSS 选择器提取正文并转换为 Quill Delta 格式

#### Scenario: Readability 通用抓取成功
- **WHEN** 用户确认一个有效 URL 且无专用提取器或规则模板匹配
- **THEN** 系统 SHALL 使用 Readability 算法自动提取正文，转换为 Quill Delta 格式

#### Scenario: 抓取失败（网络错误）
- **WHEN** 网络请求失败（超时、无网络等）
- **THEN** 系统显示 SnackBar 提示"网络错误，请检查网络连接"

#### Scenario: 抓取失败（无法提取）
- **WHEN** 所有提取器均无法提取有效内容
- **THEN** 系统显示 SnackBar 提示"无法提取该网页内容"

#### Scenario: 提取器降级
- **WHEN** 首选提取器执行失败
- **THEN** 系统 SHALL 尝试下一个匹配的提取器，直至 Readability 兜底
