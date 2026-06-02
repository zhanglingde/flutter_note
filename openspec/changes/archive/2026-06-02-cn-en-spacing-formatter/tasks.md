## 1. 格式化工具类

- [x] 1.1 创建 `lib/utils/cn_en_formatter.dart`，实现中英文边界空格插入算法（正则匹配 + 替换）
- [x] 1.2 添加跳过逻辑：行内代码、代码块、Embed 节点不处理
- [x] 1.3 添加单元测试验证格式化规则

## 2. 编辑器集成

- [x] 2.1 在 `rich_text_editor.dart` 工具栏右侧添加格式化按钮
- [x] 2.2 实现点击回调：遍历 Document 节点，对文本 Leaf 执行格式化，单次 compose 应用
- [x] 2.3 验证格式化操作可通过 Ctrl+Z 撤销
