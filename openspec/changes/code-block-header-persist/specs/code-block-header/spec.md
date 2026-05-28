## ADDED Requirements

### Requirement: 代码块 header 显示
每个代码块 SHALL 在其上方显示一个紧贴的 header 区域，包含语言标识标签和复制按钮。header SHALL 使用与代码块一致的背景色系，形成视觉上的整体。

#### Scenario: 代码块始终显示 header
- **WHEN** 文档中存在代码块
- **THEN** 每个代码块上方都显示 header，不依赖光标位置

#### Scenario: header 紧贴代码块
- **WHEN** 代码块渲染时
- **THEN** header 区域与代码块内容区域之间无间距，视觉上形成一个完整的矩形

### Requirement: header 语言标签
header 左侧 SHALL 显示当前代码块的语言名称（大写），点击后弹出语言选择菜单。选择新语言后，header 立即更新显示。

#### Scenario: 点击语言标签弹出选择器
- **WHEN** 用户点击 header 中的语言标签
- **THEN** 弹出包含所有支持语言列表的菜单，当前语言高亮标记

#### Scenario: 选择新语言后更新显示
- **WHEN** 用户从菜单中选择一个新语言（如 "python"）
- **THEN** header 中的语言标签立即更新为 "PYTHON"，代码块内语法高亮也相应更新

### Requirement: header 复制按钮
header 右侧 SHALL 显示一个复制图标按钮，点击后将该代码块的纯文本内容复制到剪贴板，并显示复制成功提示。

#### Scenario: 点击复制按钮
- **WHEN** 用户点击 header 中的复制图标
- **THEN** 该代码块的代码文本（不含语言标识和格式）被复制到剪贴板，页面显示"复制成功"提示

### Requirement: 语言持久化
代码块的语言设置 SHALL 通过 `code-block-lang` delta 属性持久化。文档保存后重新打开时，SHALL 正确恢复每个代码块的语言设置。

#### Scenario: 文档重新打开后语言保持
- **WHEN** 用户将代码块语言改为 "python" 后保存文档并重新打开
- **THEN** 代码块 header 显示 "PYTHON"，代码内容使用 Python 语法高亮

#### Scenario: 新建代码块默认语言
- **WHEN** 用户创建一个新的代码块
- **THEN** 代码块默认语言为 "dart"，header 显示 "DART"

### Requirement: 移除工具栏中的代码块工具条
主工具栏下方的代码块专属工具条 SHALL 被移除。语言选择和复制功能统一由代码块 header 提供。

#### Scenario: 光标在代码块内时无额外工具条
- **WHEN** 用户将光标移入代码块
- **THEN** 主工具栏下方不显示任何代码块专属工具条，语言标识和复制按钮仅在代码块 header 中

### Requirement: 移除代码块第一行的语言 pill
代码块第一行的语言小标签（leading pill）SHALL 被移除，语言信息统一由 header 显示。

#### Scenario: 代码块第一行无语言 pill
- **WHEN** 代码块渲染时
- **THEN** 代码块第一行左侧不显示小的语言标签角标，语言信息仅在上方 header 中
