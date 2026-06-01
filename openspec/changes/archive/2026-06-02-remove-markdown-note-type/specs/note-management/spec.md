## MODIFIED Requirements

### Requirement: 创建笔记
系统 SHALL 在用户点击新建按钮后直接创建富文本类型的笔记并打开编辑器。

#### Scenario: 点击新建按钮直接创建富文本笔记
- **WHEN** 用户点击新建笔记按钮
- **THEN** 系统直接创建一个新的富文本笔记（type = 'rich_text'，content = '[]'）
- **AND** 打开编辑器进入编辑状态
- **AND** 不显示笔记类型选择对话框
