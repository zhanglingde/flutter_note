# 网页剪藏规格

### Requirement: 工具栏剪藏图标按钮
系统 SHALL 在富文本编辑器工具栏左侧区域（图片按钮之后）显示一个 `LucideIcons.link2` 图标按钮，尺寸为 20。

#### Scenario: 图标按钮可见
- **WHEN** 用户打开任意笔记进入编辑状态
- **THEN** 工具栏左侧区域在图片按钮之后显示 link2 图标按钮

#### Scenario: 点击图标打开弹窗
- **WHEN** 用户点击 link2 图标按钮
- **THEN** 弹出链接输入对话框，包含 URL 输入框和"确定"按钮

### Requirement: 链接输入弹窗
系统 SHALL 提供一个对话框，包含 URL 文本输入框和确认/取消按钮，支持用户输入网页链接。

#### Scenario: 输入有效 URL 并确认
- **WHEN** 用户输入一个以 `http://` 或 `https://` 开头的 URL 并点击"确定"
- **THEN** 系统关闭弹窗，开始抓取网页内容，并在工具栏区域显示加载指示器

#### Scenario: 输入空 URL 并确认
- **WHEN** 用户未输入任何内容直接点击"确定"
- **THEN** 系统不发起请求，输入框保持焦点

#### Scenario: 点击取消
- **WHEN** 用户点击弹窗中的"取消"按钮或点击弹窗外部区域
- **THEN** 系统关闭弹窗，不执行任何操作

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

### Requirement: 富文本格式插入
系统 SHALL 将提取的网页正文以 Quill Delta 格式插入编辑器，保留标题、段落、粗体、斜体、列表、链接等格式。

#### Scenario: 插入带格式的正文
- **WHEN** API 返回包含标题、段落、粗体、列表等 Markdown 格式的内容
- **THEN** 系统将这些格式正确转换为 Quill Delta 属性（header、bold、italic、list、link 等）并插入编辑器

#### Scenario: 插入后附加来源链接
- **WHEN** 正文内容成功插入编辑器
- **THEN** 系统在插入内容末尾附加一行来源信息，格式为"来源：[URL](URL)"

### Requirement: 加载状态指示
系统 SHALL 在网页内容抓取期间显示加载状态，并阻止用户重复触发剪藏操作。

#### Scenario: 加载中显示指示器
- **WHEN** 系统正在抓取网页内容
- **THEN** link2 图标按钮显示加载指示器（旋转动画），且不可再次点击

#### Scenario: 加载完成后恢复
- **WHEN** 抓取操作完成（成功或失败）
- **THEN** link2 图标按钮恢复为正常状态，用户可再次点击

### Requirement: HTML video 标签转换为视频 embed
HTML 转 Delta 过程中，遇到 `<video>` 标签 SHALL 提取视频源 URL 并生成视频 embed 节点，而非跳过或仅提取文本。

#### Scenario: 处理带 src 的 video 标签
- **WHEN** HTML 中包含 `<video src="url">`
- **THEN** 生成 `BlockEmbed('video', '{"source": "url", "width": 400}')`

#### Scenario: 处理带 source 子标签的 video
- **WHEN** HTML 中包含 `<video><source src="url"></video>`
- **THEN** 使用第一个 source 的 src 生成视频 embed
