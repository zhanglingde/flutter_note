# 中英文混排空格格式化规格

## Purpose

提供中英文混排文本的自动空格格式化能力，在中文与英文/数字边界插入空格，遵循中文文案排版指北。

## Requirements

### Requirement: 中英文边界空格插入
系统 SHALL 在中文字符与半角英文字母/数字相邻时，在它们之间插入一个半角空格。

#### Scenario: 中文字符后紧跟英文字母
- **WHEN** 文本包含 `你好world`
- **THEN** 格式化后变为 `你好 world`

#### Scenario: 英文字母后紧跟中文字符
- **WHEN** 文本包含 `hello世界`
- **THEN** 格式化后变为 `hello 世界`

#### Scenario: 中文字符后紧跟数字
- **WHEN** 文本包含 `第3章`
- **THEN** 格式化后变为 `第 3 章`

#### Scenario: 数字后紧跟中文字符
- **WHEN** 文本包含 `2025年`
- **THEN** 格式化后变为 `2025 年`

### Requirement: 不重复添加空格
系统 SHALL 在相邻字符之间已有空格时不重复添加。

#### Scenario: 已有空格不重复
- **WHEN** 文本包含 `你好 world`
- **THEN** 格式化后保持 `你好 world` 不变

### Requirement: 不修改中文标点间距
系统 SHALL 不在中文字符与全角标点之间添加空格。

#### Scenario: 全角标点保持不变
- **WHEN** 文本包含 `你好，世界`
- **THEN** 格式化后保持 `你好，世界` 不变

### Requirement: 跳过行内代码
系统 SHALL 不修改行内代码（inlineCode）中的内容。

#### Scenario: 行内代码不处理
- **WHEN** 文本中包含行内代码格式的 `foo你好bar`
- **THEN** 格式化后行内代码内容保持 `foo你好bar` 不变

### Requirement: 跳过代码块
系统 SHALL 不修改代码块（codeBlock）中的内容。

#### Scenario: 代码块不处理
- **WHEN** 代码块中包含 `int第3章 = 1`
- **THEN** 格式化后代码块内容保持不变

### Requirement: 跳过 Embed 节点
系统 SHALL 不修改图片、链接等 Embed 节点。

#### Scenario: 图片 embed 不受影响
- **WHEN** 文档中包含图片 embed
- **THEN** 格式化后图片 embed 保持不变

### Requirement: 可撤销
系统 SHALL 将整个格式化操作作为一个 compose 操作，使其可通过一次 undo 撤销。

#### Scenario: 撤销格式化
- **WHEN** 用户执行格式化后按 Ctrl+Z
- **THEN** 整个格式化操作被撤销，文档恢复到格式化前的状态
