## MODIFIED Requirements

### Requirement: 工具栏可见性
系统应当在编辑器上方显示格式化工具栏。

#### Scenario: 聚焦时显示工具栏
- **WHEN** 富文本编辑器获得焦点
- **THEN** 格式化工具栏可见且可访问

#### Scenario: 工具栏按钮反映当前格式
- **WHEN** 光标位于粗体文本上
- **THEN** 粗体按钮显示激活状态

#### Scenario: 显示格式化按钮
- **WHEN** 富文本编辑器加载完成
- **THEN** 工具栏右侧显示中英文格式化按钮

#### Scenario: 点击格式化按钮
- **WHEN** 用户点击格式化按钮
- **THEN** 系统对当前文档执行中英文混排空格格式化
