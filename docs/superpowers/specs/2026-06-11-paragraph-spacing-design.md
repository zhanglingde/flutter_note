# 段间距功能设计

## 概述

在富文本编辑器中为所有块级元素（段落、标题、列表、引用、代码块、缩进块）统一增加 8px 底部间距，使文档排版更清晰。

## 需求

- 全局固定间距：8px
- 作用于所有段落之间（正文、标题、列表、引用、代码块等）
- 不需要用户调节，固定值即可

## 技术方案

### 修改文件

`lib/widgets/rich_text_editor.dart`（第 1226-1239 行）

### 实现方式

利用 flutter_quill 的 `QuillStyles` + `DefaultStyles` 机制，通过 `merge` 方法覆盖所有块级类型的 `verticalSpacing` 属性。

**核心改动：**

1. 定义统一间距常量 `const paragraphSpacing = VerticalSpacing(0, 8)`
2. 在现有 `QuillStyles` merge 代码块中，覆盖以下块级类型的 `verticalSpacing`：
   - `paragraph` — 正文段落
   - `h1` ~ `h6` — 各级标题
   - `lists` — 有序/无序/待办列表
   - `quote` — 引用块
   - `code` — 代码块（保留已有背景色自定义）
   - `indent` — 缩进块
3. 对每种块类型，仅修改 `verticalSpacing`，保留其他属性不变（style、horizontalSpacing、lineSpacing、decoration）

**注意事项：**
- `lists` 类型使用 `DefaultListBlockStyle`，需要额外传递 `checkboxUIBuilder` 参数
- `code` 类型保留已有的背景色和圆角自定义逻辑

### 不影响的内容

- 行间距（lineSpacing）
- 水平间距（horizontalSpacing）
- 字体样式（style）
- 装饰（decoration）
- 编辑器内边距（padding）

## 测试验证

运行 `flutter run -d windows`，创建包含以下内容的笔记进行验证：

- 多个正文段落（应相互间隔 8px）
- 标题后跟正文（应间隔 8px）
- 列表项之间（应间隔 8px）
- 引用块（应间隔 8px）
- 代码块（应间隔 8px，保留背景色）
- 混合排版场景（各元素间距一致）
