# 笔记列表右键菜单

## 背景

桌面端点击笔记列表中的笔记时，最近的变更（commit `79c6c78`）将其改为"在当前活动标签页中替换内容打开"。但用户有时希望强制在新标签页打开（保留原标签页内容），且当前删除入口较分散（图标按钮、滑动、编辑器菜单）。需要通过右键菜单提供这两个常用操作的快捷入口。

移动端目前依赖 `Dismissible` 滑动和 trailing 图标按钮删除，缺少长按快捷入口。

## 目标

- **桌面端**：在笔记列表（list + waterfall 两种视图）上右键弹出通用菜单，包含「在新标签页打开」「删除」两项；删除项使用红色样式
- **移动端**：在笔记列表上长按弹出菜单，仅包含「删除」一项
- **删除行为**：右键/长按菜单的删除项**无确认对话框直接删除**（后续会由回收站功能兜底）
- **回归保护**：现有删除路径（滑动、图标按钮、编辑器菜单）保留确认对话框，无回归

## 方案选型

选用 Flutter 原生 `showMenu<T>(context, position, items)`：

- 零新增依赖
- 与项目现有 `PopupMenuButton` 视觉风格一致
- 支持基于点击坐标精准定位菜单
- 红色样式可通过 `PopupMenuItem` 子组件颜色实现，已有先例（`home_screen.dart:495-503` 的编辑器删除菜单）

排除方案：第三方包 `context_menus`（引入依赖、风格不一致）；`OverlayEntry` 自定义（工作量大）。

## 架构

### 文件结构

| 文件 | 职责 |
|------|------|
| `lib/screens/home_screen.dart` | 新增 `_showNoteContextMenu`、抽取 `_performDeleteNote`、修改两个 `_build*Card` 方法 |

无新增文件，无新增依赖，无数据模型变更。

### 通用菜单方法

在 `_HomeScreenState` 中新增：

```dart
void _showNoteContextMenu({
  required Note note,
  required Offset position,
  required bool includeOpenInNewTab,
}) async {
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx, position.dy, position.dx, position.dy,
    ),
    items: [
      if (includeOpenInNewTab)
        const PopupMenuItem(
          value: 'openInNewTab',
          child: ListTile(
            leading: Icon(Icons.tab),
            title: Text('在新标签页打开'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(Icons.delete, color: Colors.red),
          title: Text('删除', style: TextStyle(color: Colors.red)),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );

  if (!mounted) return;
  switch (action) {
    case 'openInNewTab':
      _addNewTab(note);  // 复用现有方法（含 LRU 淘汰）
      break;
    case 'delete':
      _performDeleteNote(note);  // 无确认直接删
      break;
  }
}
```

### 删除逻辑重构

抽取 `_performDeleteNote`（无确认版本）作为底层执行方法，`_deleteNote`（带确认）复用之：

```dart
/// 执行删除（无确认对话框）
Future<void> _performDeleteNote(Note note) async {
  final result = await widget.storageService.deleteNote(note.id);
  if (result.success) {
    await ImageStorageService().deleteImagesForNote(note.id);
    await VideoStorageService().deleteVideosForNote(note.id);
    if (_tabs.any((t) => t.id == note.id)) {
      _closeTabWithoutSave(note.id);
    }
    _loadNotes();
  } else if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.error ?? '删除笔记失败')),
    );
  }
}

/// 带确认对话框的删除（保留现有行为）
Future<void> _deleteNote(Note note) async {
  final confirmed = await showDialog<bool>(...);  // 现有对话框不变
  if (confirmed == true) {
    await _performDeleteNote(note);
  }
}
```

### 视图集成

**List 视图（`_buildNoteCard`）**：在 `Dismissible` 外层包裹 `GestureDetector`，捕获桌面右键和移动长按：

```dart
GestureDetector(
  onSecondaryTapDown: isDesktop
      ? (d) => _showNoteContextMenu(
            note: note,
            position: d.globalPosition,
            includeOpenInNewTab: true)
      : null,
  onLongPressEnd: !isDesktop
      ? (d) => _showNoteContextMenu(
            note: note,
            position: d.globalPosition,
            includeOpenInNewTab: false)
      : null,
  child: /* 原有 Dismissible+ListTile */,
)
```

**Waterfall 视图（`_buildWaterfallCard`）**：现有 `GestureDetector` 已有 `onSecondaryTap`，替换为 `onSecondaryTapDown` 并新增 `onLongPressEnd`：

```dart
// 当前：onSecondaryTap: () => _deleteNote(note),
// 改为：
onSecondaryTapDown: isDesktop
    ? (d) => _showNoteContextMenu(
          note: note,
          position: d.globalPosition,
          includeOpenInNewTab: true)
    : null,
onLongPressEnd: !isDesktop
    ? (d) => _showNoteContextMenu(
          note: note,
          position: d.globalPosition,
          includeOpenInNewTab: false)
    : null,
```

`isDesktop` 通过 `MediaQuery.of(context).size.width > 768` 判断（与 `_buildDesktopLayout` 现有逻辑一致）。

## 数据流

```
桌面右键 → onSecondaryTapDown 捕获 globalPosition
                ↓
        _showNoteContextMenu(includeOpenInNewTab: true)
                ↓
        showMenu 弹出 ["新标签", "删除(红色)"]
                ↓
    ┌───────────┴───────────┐
    ↓                       ↓
_addNewTab(note)       _performDeleteNote(note)
(强制新建标签页)        (无确认直接删)

移动长按 → onLongPressEnd → _showNoteContextMenu(includeOpenInNewTab: false)
                              ↓
                      showMenu 仅 ["删除(红色)"]
                              ↓
                      _performDeleteNote(note)
```

## 错误处理

- 删除失败：保留现有 SnackBar 提示 `result.error ?? '删除笔记失败'`
- `showMenu` 返回 null（点击外部取消）：switch 不匹配任何 case，无副作用
- `await showMenu` 后通过 `if (!mounted) return` 守卫，避免菜单关闭后 widget 已销毁

## 影响范围

- 改动文件：`lib/screens/home_screen.dart` 一个
- **回归保护**：
  - 滑动删除（`Dismissible.onDismissed`）→ `_deleteNote`（保留确认）
  - trailing 图标按钮（`IconButton.onPressed`）→ `_deleteNote`（保留确认）
  - 编辑器 `PopupMenuButton` 的「删除」项 → `_deleteNote`（保留确认）
- **行为变更（预期）**：waterfall 视图右键原本调用 `_deleteNote`（带确认），改为弹菜单→删除项无确认。这是本次需求的一部分
- 无数据模型变更，无新增依赖

## 测试要点

- 桌面端 list 视图右键 → 菜单含「新标签」「删除」，删除为红色
- 桌面端 waterfall 视图右键 → 同上
- 移动端 list 视图长按 → 菜单只有「删除」
- 移动端 waterfall 视图长按 → 同上
- 点击「新标签」→ 在新标签页打开该笔记（即使已有活动标签页）
- 点击「删除」→ 直接删除，无对话框
- 点击菜单外部 → 菜单关闭，无副作用
- 现有删除路径仍弹确认对话框（无回归）
