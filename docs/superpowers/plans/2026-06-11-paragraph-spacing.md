# 段间距功能实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为富文本编辑器中所有块级元素统一增加 8px 底部段间距。

**架构：** 利用 flutter_quill 的 `QuillStyles` + `DefaultStyles` merge 机制，覆盖所有块级类型（paragraph、h1-h6、lists、quote、code、indent）的 `verticalSpacing` 为 `VerticalSpacing(0, 8)`。

**技术栈：** Flutter、flutter_quill 11.5.0、Dart

---

### 任务 1：修改 QuillStyles 增加段间距

**文件：**
- 修改：`lib/widgets/rich_text_editor.dart:1226-1239`

- [ ] **步骤 1：编写实现代码**

将第 1226-1239 行的 QuillStyles merge 代码从：

```dart
final defaultStyles = DefaultStyles.getInstance(context);
return QuillStyles(
    data: defaultStyles.merge(DefaultStyles(
      code: DefaultTextBlockStyle(
        defaultStyles.code!.style,
        defaultStyles.code!.horizontalSpacing,
        defaultStyles.code!.verticalSpacing,
        defaultStyles.code!.lineSpacing,
        const BoxDecoration(
          color: Color(0xFFEDEDED),
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
    )),
```

替换为：

```dart
final defaultStyles = DefaultStyles.getInstance(context);
const paragraphSpacing = VerticalSpacing(0, 8);
return QuillStyles(
    data: defaultStyles.merge(DefaultStyles(
      paragraph: DefaultTextBlockStyle(
        defaultStyles.paragraph!.style,
        defaultStyles.paragraph!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.paragraph!.lineSpacing,
        defaultStyles.paragraph!.decoration,
      ),
      h1: DefaultTextBlockStyle(
        defaultStyles.h1!.style,
        defaultStyles.h1!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.h1!.lineSpacing,
        defaultStyles.h1!.decoration,
      ),
      h2: DefaultTextBlockStyle(
        defaultStyles.h2!.style,
        defaultStyles.h2!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.h2!.lineSpacing,
        defaultStyles.h2!.decoration,
      ),
      h3: DefaultTextBlockStyle(
        defaultStyles.h3!.style,
        defaultStyles.h3!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.h3!.lineSpacing,
        defaultStyles.h3!.decoration,
      ),
      h4: DefaultTextBlockStyle(
        defaultStyles.h4!.style,
        defaultStyles.h4!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.h4!.lineSpacing,
        defaultStyles.h4!.decoration,
      ),
      h5: DefaultTextBlockStyle(
        defaultStyles.h5!.style,
        defaultStyles.h5!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.h5!.lineSpacing,
        defaultStyles.h5!.decoration,
      ),
      h6: DefaultTextBlockStyle(
        defaultStyles.h6!.style,
        defaultStyles.h6!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.h6!.lineSpacing,
        defaultStyles.h6!.decoration,
      ),
      lists: DefaultListBlockStyle(
        defaultStyles.lists!.style,
        defaultStyles.lists!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.lists!.lineSpacing,
        defaultStyles.lists!.decoration,
        defaultStyles.lists!.checkboxUIBuilder,
      ),
      quote: DefaultTextBlockStyle(
        defaultStyles.quote!.style,
        defaultStyles.quote!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.quote!.lineSpacing,
        defaultStyles.quote!.decoration,
      ),
      code: DefaultTextBlockStyle(
        defaultStyles.code!.style,
        defaultStyles.code!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.code!.lineSpacing,
        const BoxDecoration(
          color: Color(0xFFEDEDED),
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
      indent: DefaultTextBlockStyle(
        defaultStyles.indent!.style,
        defaultStyles.indent!.horizontalSpacing,
        paragraphSpacing,
        defaultStyles.indent!.lineSpacing,
        defaultStyles.indent!.decoration,
      ),
    )),
```

- [ ] **步骤 2：运行代码分析**

运行：`flutter analyze`
预期：无错误

- [ ] **步骤 3：运行应用验证效果**

运行：`flutter run -d windows`
验证：
1. 创建包含多个正文段落的笔记 → 段落之间应有 8px 间距
2. 添加标题（h1/h2/h3）后跟正文 → 标题与正文间距 8px
3. 添加有序/无序列表 → 列表项之间间距 8px
4. 添加引用块 → 引用块间距 8px
5. 添加代码块 → 代码块间距 8px，背景色仍为灰色

- [ ] **步骤 4：Commit**

```bash
git add lib/widgets/rich_text_editor.dart
git commit -m "feat: 为所有块级元素增加 8px 段间距"
```
