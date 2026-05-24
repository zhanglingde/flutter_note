# markdown-auto-convert

富文本编辑器中的 Markdown 语法自动检测和转换能力。

## Requirements

### Requirement: Markdown 语法自动检测

系统 SHALL 在富文本编辑器中检测用户输入的 Markdown 语法。

#### Scenario: 检测标题语法
- **WHEN** 用户在行首输入 `# `、`## ` 或 `### ` 后按空格键
- **THEN** 系统识别为标题语法并准备转换

#### Scenario: 检测粗体语法
- **WHEN** 用户输入 `**文本**` 或 `__文本__` 格式
- **THEN** 系统识别为粗体语法并准备转换

#### Scenario: 检测斜体语法
- **WHEN** 用户输入 `*文本*` 或 `_文本_` 格式
- **THEN** 系统识别为斜体语法并准备转换

#### Scenario: 检测删除线语法
- **WHEN** 用户输入 `~~文本~~` 格式
- **THEN** 系统识别为删除线语法并准备转换

#### Scenario: 检测代码语法
- **WHEN** 用户输入 `` `代码` `` 格式
- **THEN** 系统识别为行内代码语法并准备转换

#### Scenario: 检测无序列表语法
- **WHEN** 用户在行首输入 `- ` 或 `* ` 后按空格键
- **THEN** 系统识别为无序列表语法并准备转换

#### Scenario: 检测有序列表语法
- **WHEN** 用户在行首输入 `1. ` 后按空格键
- **THEN** 系统识别为有序列表语法并准备转换

#### Scenario: 检测引用语法
- **WHEN** 用户在行首输入 `> ` 后按空格键
- **THEN** 系统识别为引用语法并准备转换

### Requirement: Markdown 语法自动转换

系统 SHALL 将检测到的 Markdown 语法转换为对应的富文本格式。

#### Scenario: 转换标题
- **WHEN** 检测到标题语法并触发转换
- **THEN** 系统将 `# 标题` 转换为 H1 格式的富文本
- **AND** 系统将 `## 标题` 转换为 H2 格式的富文本
- **AND** 系统将 `### 标题` 转换为 H3 格式的富文本

#### Scenario: 转换粗体
- **WHEN** 检测到粗体语法并触发转换
- **THEN** 系统将 `**文本**` 转换为粗体格式的富文本
- **AND** 删除 Markdown 标记符号

#### Scenario: 转换斜体
- **WHEN** 检测到斜体语法并触发转换
- **THEN** 系统将 `*文本*` 转换为斜体格式的富文本
- **AND** 删除 Markdown 标记符号

#### Scenario: 转换删除线
- **WHEN** 检测到删除线语法并触发转换
- **THEN** 系统将 `~~文本~~` 转换为删除线格式的富文本
- **AND** 删除 Markdown 标记符号

#### Scenario: 转换行内代码
- **WHEN** 检测到代码语法并触发转换
- **THEN** 系统将 `` `代码` `` 转换为代码格式的富文本
- **AND** 删除 Markdown 标记符号

#### Scenario: 转换无序列表
- **WHEN** 检测到无序列表语法并触发转换
- **THEN** 系统将该行转换为无序列表项

#### Scenario: 转换有序列表
- **WHEN** 检测到有序列表语法并触发转换
- **THEN** 系统将该行转换为有序列表项

#### Scenario: 转换引用
- **WHEN** 检测到引用语法并触发转换
- **THEN** 系统将该行转换为引用块

### Requirement: 转换功能开关

系统 SHALL 提供开关让用户启用或禁用 Markdown 自动转换功能。

#### Scenario: 默认启用
- **WHEN** 用户首次使用富文本编辑器
- **THEN** Markdown 自动转换功能默认启用

#### Scenario: 禁用转换功能
- **WHEN** 用户在工具栏点击开关禁用功能
- **THEN** 系统停止自动转换 Markdown 语法
- **AND** 用户输入的 Markdown 符号保持原样

#### Scenario: 启用转换功能
- **WHEN** 用户在工具栏点击开关启用功能
- **THEN** 系统恢复自动转换 Markdown 语法

#### Scenario: 开关状态持久化
- **WHEN** 用户切换开关状态
- **THEN** 系统保存设置到本地存储
- **AND** 下次打开编辑器时恢复用户的选择

### Requirement: 复合输入法兼容

系统 SHALL 正确处理中文等复合输入法的输入。

#### Scenario: 中文输入过程中不触发转换
- **WHEN** 用户使用中文输入法正在输入（存在 composing 状态）
- **THEN** 系统不触发 Markdown 转换

#### Scenario: 中文输入完成后触发转换
- **WHEN** 用户完成中文输入（composing 状态结束）并输入空格或回车
- **THEN** 系统正常检测和转换 Markdown 语法

### Requirement: 撤销重做支持

系统 SHALL 保持 Markdown 转换操作的撤销/重做功能正常工作。

#### Scenario: 撤销转换操作
- **WHEN** Markdown 语法被转换为富文本后
- **AND** 用户按下撤销快捷键（Ctrl+Z / Cmd+Z）
- **THEN** 系统撤销转换，恢复原始 Markdown 文本

#### Scenario: 重做转换操作
- **WHEN** 用户撤销了转换操作后
- **AND** 用户按下重做快捷键（Ctrl+Y / Cmd+Shift+Z）
- **THEN** 系统重新应用转换
