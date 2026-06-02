## Why

中英文混排时缺少空格会降低可读性，手动逐处添加空格效率低且容易遗漏。需要一个一键格式化工具自动在中文字符与半角英文字母/数字之间插入空格。

## What Changes

- 在富文本编辑器工具栏右侧新增「格式化」按钮（文本格式化图标）
- 点击后对当前文档内容执行中英文混排空格格式化，自动在中文字符与半角英文字母/数字相邻处插入空格
- 格式化时跳过行内代码、代码块、链接、图片等特殊内容，不做破坏性处理
- 格式化操作可撤销（通过 Quill 的 undo）

## Capabilities

### New Capabilities
- `cn-en-spacing`: 中英文混排空格格式化能力，定义格式化规则和跳过规则

### Modified Capabilities
- `rich-text-editing`: 工具栏新增格式化按钮

## Impact

- 新增工具类 `TextFormatter`，负责中英文混排空格格式化逻辑
- 修改 `rich_text_editor.dart` 工具栏，新增格式化按钮
- 操作 Quill Document Delta，不涉及存储层变更
