# 大纲侧边栏功能设计

## 概述

在富文本编辑器顶部工具栏右侧新增「大纲」按钮，点击后在编辑区右侧展开大纲面板，显示文档的 h1/h2/h3 标题层级。面板支持可拖拽宽度、点击跳转、光标跟随高亮、实时更新。

## 布局结构

```
Column [Toolbar(48px) + EditorArea(Expanded)]
  Toolbar:
    Row [左侧(段落|格式|图片) | 右侧(Markdown开关 | 大纲按钮)]
  EditorArea:
    Row [QuillEditor(Expanded) | 拖拽分隔条(4px) | OutlinePanel(可变宽度)]
```

- 大纲按钮位于 Markdown 开关按钮左侧
- 面板默认隐藏，点击按钮 toggle
- 编辑区域自动缩窄/恢复

## 交互行为

| 行为 | 描述 |
|------|------|
| 切换 | 点击「大纲」按钮 → 面板展开/收起 |
| 跳转 | 点击大纲标题 → 编辑器滚动到对应位置 |
| 高亮 | 光标移动时 → 大纲自动高亮当前所在标题 |
| 拖拽宽度 | 拖拽分隔条 → 调整宽度（160px~400px），默认 240px |
| 实时更新 | 标题编辑/增删后大纲自动刷新 |
| 空状态 | 无标题时显示"暂无标题"提示 |

## 数据模型

大纲项数据结构：

```dart
class OutlineItem {
  final int level;       // 1, 2, 3 对应 h1, h2, h3
  final String text;     // 标题文本
  final int offset;      // 在文档中的字符偏移量
}
```

## 标题提取逻辑

遍历 `QuillController.document.root` 的子节点：
- 对每个 `Line` 节点检查 `style.attributes['header']`
- 如果值为 1/2/3，提取该行的纯文本内容和偏移量
- 构建 `List<OutlineItem>`

触发时机：
- `_controller.addListener` 中检测文档变化时重新提取
- 使用防抖（300ms）避免频繁重建

## 光标跟随高亮

- 监听 `_controller.selection` 变化
- 获取当前光标 offset
- 遍历 OutlineItem 列表，找到 offset 所在的标题区间
- 高亮该标题项

## 组件拆分

1. **OutlineSidebar**（StatefulWidget）— 大纲面板主体
   - 管理展开/收起状态
   - 管理面板宽度（含拖拽）
   - 包含标题列表和空状态

2. **OutlineItemWidget** — 单个大纲项
   - 根据 level 缩进
   - 高亮状态样式
   - 点击跳转

## 文件变更

| 文件 | 变更 |
|------|------|
| `lib/widgets/rich_text_editor.dart` | 在工具栏添加大纲按钮，编辑区 Row 包含 OutlineSidebar |
| `lib/widgets/outline_sidebar.dart` | 新建 — 大纲面板组件 |

## 不在范围内

- 大纲面板内的搜索/过滤
- 大纲项的拖拽排序
- Markdown 编辑器的大纲支持
