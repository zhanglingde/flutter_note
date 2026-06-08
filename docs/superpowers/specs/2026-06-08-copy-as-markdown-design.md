# 复制为 Markdown 功能设计

## 概述

在编辑器右上角工具菜单中增加"复制为 Markdown"功能，将当前笔记的全部正文转换为 Markdown 格式并复制到系统剪贴板。

## 需求

- **复制范围**：整篇笔记内容（不含标题）
- **菜单位置**：桌面端和移动端编辑页面的工具菜单
- **格式支持**：基本 Markdown（标题、粗体、斜体、删除线、列表、代码块、引用、图片、链接）

## 方案

自定义 Delta → Markdown 转换器，与现有 `markdown_to_delta.dart` 对称实现，无外部依赖。

## 实现细节

### 1. Delta → Markdown 转换器

新建 `lib/utils/delta_to_markdown.dart`，提供函数：

```dart
String deltaToMarkdown(String deltaJson)
```

**格式映射表**：

| Quill Delta 属性 | Markdown 输出 |
|---|---|
| `header: 1` | `# text` |
| `header: 2` | `## text` |
| `header: 3` | `### text` |
| `bold: true` | `**text**` |
| `italic: true` | `*text*` |
| `strike: true` | `~~text~~` |
| `code: true`（行内） | `` `text` `` |
| `list: "ordered"` | `1. item` |
| `list: "bullet"` | `- item` |
| `blockquote: true` | `> text` |
| `code-block: true` | `` ```\ncode\n``` `` |
| `image` insert | `![image](url)` |
| `link: href` | `[text](href)` |

**算法**：

1. 解析 Delta JSON 为操作列表
2. 将操作按行分组（以 `\n` insert 分隔）
3. 每行根据属性确定块级格式（header/list/blockquote/code-block）
4. 行内文本根据 attributes 添加行内格式标记
5. 拼接所有行为最终 Markdown 文本

### 2. 菜单项

**桌面端**（`home_screen.dart` `_buildEditorPanelWithTabs()`）：
- 在"复制笔记"和"删除"之间添加"复制为 Markdown"菜单项
- 图标：`Icons.data_object`
- 值：`'copyMarkdown'`

**移动端**（`home_screen.dart` `_EditorScreenWrapperState`）：
- 在"删除"菜单项前添加"复制为 Markdown"菜单项
- 使用相同的图标和值

### 3. 处理逻辑

在 `_handleEditorAction()`（桌面端）和 `_handleMenuAction()`（移动端）中添加对 `'copyMarkdown'` 的处理：

1. 获取当前笔记的 `content`（Delta JSON 字符串）
2. 调用 `deltaToMarkdown(content)` 得到 Markdown 文本
3. 使用 `Clipboard.setData(ClipboardData(text: markdown))` 复制到系统剪贴板
4. 显示 SnackBar 提示"已复制为 Markdown"

## 涉及文件

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `lib/utils/delta_to_markdown.dart` | 新建 | Delta → Markdown 转换器 |
| `lib/screens/home_screen.dart` | 修改 | 桌面端和移动端菜单项 + 处理逻辑 |
