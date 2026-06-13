# 笔记列表右键菜单 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 桌面端右键笔记（list + waterfall 视图）弹出「新标签/删除」菜单，移动端长按弹出仅含「删除」的菜单，删除项红色样式且无确认直接执行。

**架构：** 在 `_HomeScreenState` 新增通用方法 `_showNoteContextMenu`，抽取 `_performDeleteNote` 作为无确认删除的底层执行方法（现有 `_deleteNote` 复用之并保留确认对话框）。两个视图卡片通过 `GestureDetector` 的 `onSecondaryTapDown`（桌面）/ `onLongPressEnd`（移动）触发菜单。

**技术栈：** Flutter，无新增依赖。

---

## 测试策略说明

项目当前无 widget test 基础设施（仅 Note 模型和 cn_en_formatter 单元测试），且 `HomeScreen` 耦合 `NoteStorageService`（sqflite_ffi）、`ImageStorageService`、`VideoStorageService`、`SharedPreferences`，建立 mock 体系超出本次范围。

本次变更主体是 UI 交互，采用以下验证方式替代自动化测试：
- 每个代码步骤后运行 `flutter analyze`
- 最后一个任务为详细手动验证清单，覆盖设计文档全部测试要点
- 频繁 commit，每任务一个独立可回滚的提交

## 文件结构

| 文件 | 职责 |
|------|------|
| `lib/screens/home_screen.dart` | 抽取 `_performDeleteNote`、新增 `_showNoteContextMenu`、修改 `_buildNoteCard` 和 `_buildWaterfallCard` |

无新增文件，无数据模型变更，无新增依赖。

---

## 任务 1：抽取 `_performDeleteNote` 方法

**文件：**
- 修改：`lib/screens/home_screen.dart:333-392`（`_deleteNote` 方法）

**目的：** 把 `_deleteNote` 中"确认对话框之后"的执行部分抽出来，作为无确认版本供右键菜单复用。现有调用方（滑动、图标按钮、编辑器菜单）仍走带确认的 `_deleteNote`。

- [ ] **步骤 1：在 `_deleteNote` 之前新增 `_performDeleteNote` 方法**

在 `lib/screens/home_screen.dart` 中找到 `_deleteNote` 方法（约 333 行），在其**上方**插入新方法：

```dart
  /// 执行删除（无确认对话框）—— 供右键菜单和 _deleteNote 共用
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error ?? '删除笔记失败')));
    }
  }
```

- [ ] **步骤 2：让 `_deleteNote` 复用 `_performDeleteNote`**

将 `_deleteNote` 方法中 `if (confirmed == true) { ... }` 块内的全部内容替换为单行调用 `_performDeleteNote(note)`。

修改前（约 377-391 行）：

```dart
    if (confirmed == true) {
      final result = await widget.storageService.deleteNote(note.id);
      if (result.success) {
        await ImageStorageService().deleteImagesForNote(note.id);
        await VideoStorageService().deleteVideosForNote(note.id);
        if (_tabs.any((t) => t.id == note.id)) {
          _closeTabWithoutSave(note.id);
        }
        _loadNotes();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.error ?? '删除笔记失败')));
      }
    }
```

修改后：

```dart
    if (confirmed == true) {
      await _performDeleteNote(note);
    }
```

- [ ] **步骤 3：运行 `flutter analyze` 验证无 error**

运行：`flutter analyze lib/screens/home_screen.dart`
预期：无 error（已有的 info/warning 可忽略）

- [ ] **步骤 4：Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "refactor: 抽取 _performDeleteNote 作为无确认删除的底层方法"
```

---

## 任务 2：新增 `_showNoteContextMenu` 通用菜单方法

**文件：**
- 修改：`lib/screens/home_screen.dart`（在任务 1 新增的 `_performDeleteNote` 之后插入新方法）

**目的：** 提供通用菜单入口，根据 `includeOpenInNewTab` 决定是否显示「新标签」项；菜单项的删除样式为红色（复用 `home_screen.dart:495-503` 编辑器删除菜单的写法）。

- [ ] **步骤 1：在 `_performDeleteNote` 之后新增 `_showNoteContextMenu` 方法**

在 `lib/screens/home_screen.dart` 中找到任务 1 新增的 `_performDeleteNote` 方法，在其**之后**插入：

```dart
  /// 笔记卡片右键/长按菜单
  ///
  /// [includeOpenInNewTab] 为 true 时显示「在新标签页打开」项（桌面端）；
  /// 为 false 时只显示「删除」（移动端）。
  void _showNoteContextMenu({
    required Note note,
    required Offset position,
    required bool includeOpenInNewTab,
  }) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
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
        _addNewTab(note);
        break;
      case 'delete':
        _performDeleteNote(note);
        break;
    }
  }
```

- [ ] **步骤 2：运行 `flutter analyze` 验证无 error**

运行：`flutter analyze lib/screens/home_screen.dart`
预期：无 error

- [ ] **步骤 3：Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: 新增 _showNoteContextMenu 通用右键菜单方法"
```

---

## 任务 3：list 视图集成右键 / 长按

**文件：**
- 修改：`lib/screens/home_screen.dart:792-851`（`_buildNoteCard` 方法）

**目的：** list 视图的 `ListTile` 当前无右键/长按支持，通过 `GestureDetector` 包裹整个 `Dismissible` 的 child 捕获事件。

- [ ] **步骤 1：在 `_buildNoteCard` 方法体内计算 `isDesktop`**

在 `lib/screens/home_screen.dart` 中找到 `_buildNoteCard` 方法（约 792 行），在方法体内第一行（`final title = _extractTitle(...)` 之前）插入：

```dart
    final isDesktop = MediaQuery.of(context).size.width > 768;
```

- [ ] **步骤 2：用 `GestureDetector` 包裹 `Dismissible`**

当前 `_buildNoteCard` 返回的结构是：

```dart
    return Dismissible(
      key: Key(note.id),
      ...
      child: Container(
        ...
      ),
    );
```

将其改为用 `GestureDetector` 包裹 `Dismissible`：

```dart
    return GestureDetector(
      onSecondaryTapDown: isDesktop
          ? (details) => _showNoteContextMenu(
                note: note,
                position: details.globalPosition,
                includeOpenInNewTab: true,
              )
          : null,
      onLongPressEnd: !isDesktop
          ? (details) => _showNoteContextMenu(
                note: note,
                position: details.globalPosition,
                includeOpenInNewTab: false,
              )
          : null,
      child: Dismissible(
        key: Key(note.id),
        // ... Dismissible 其余属性保持不变（direction, background, onDismissed, child）
      ),
    );
```

**注意：** 原 `Dismissible` 的所有属性（`key`、`direction`、`background`、`onDismissed`、`child`）保持原样，只是整体作为 `GestureDetector.child`。需要正确缩进。

- [ ] **步骤 3：运行 `flutter analyze` 验证无 error**

运行：`flutter analyze lib/screens/home_screen.dart`
预期：无 error

- [ ] **步骤 4：Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: list 视图笔记卡片支持桌面右键和移动长按菜单"
```

---

## 任务 4：waterfall 视图集成右键 / 长按

**文件：**
- 修改：`lib/screens/home_screen.dart:947-1029`（`_buildWaterfallCard` 方法）

**目的：** waterfall 视图当前 `onSecondaryTap` 直接调用 `_deleteNote`（带确认），改为调用 `_showNoteContextMenu` 并增加移动长按支持。

- [ ] **步骤 1：在 `_buildWaterfallCard` 方法体内计算 `isDesktop`**

在 `lib/screens/home_screen.dart` 中找到 `_buildWaterfallCard` 方法（约 947 行），在方法体内第一行（`final title = _extractTitle(...)` 之前）插入：

```dart
    final isDesktop = MediaQuery.of(context).size.width > 768;
```

- [ ] **步骤 2：替换 `onSecondaryTap` 为 `onSecondaryTapDown` 并新增 `onLongPressEnd`**

当前 `_buildWaterfallCard` 的 `GestureDetector` 是（约 953-955 行）：

```dart
    return GestureDetector(
      onTap: () => _openNote(note),
      onSecondaryTap: () => _deleteNote(note),
      child: Container(
```

改为：

```dart
    return GestureDetector(
      onTap: () => _openNote(note),
      onSecondaryTapDown: isDesktop
          ? (details) => _showNoteContextMenu(
                note: note,
                position: details.globalPosition,
                includeOpenInNewTab: true,
              )
          : null,
      onLongPressEnd: !isDesktop
          ? (details) => _showNoteContextMenu(
                note: note,
                position: details.globalPosition,
                includeOpenInNewTab: false,
              )
          : null,
      child: Container(
```

**注意：** `onTap` 保持不变；原 `onSecondaryTap` 删除。

- [ ] **步骤 3：运行 `flutter analyze` 验证无 error**

运行：`flutter analyze lib/screens/home_screen.dart`
预期：无 error

- [ ] **步骤 4：Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: waterfall 视图笔记卡片支持桌面右键和移动长按菜单"
```

---

## 任务 5：完整手动验证

**文件：** 无代码改动，运行时验证。

**目的：** 验证设计文档"测试要点"全部覆盖，且无回归。

- [ ] **步骤 1：启动 Windows 桌面应用**

运行：`flutter run -d windows`

- [ ] **步骤 2：验证桌面端 list 视图右键菜单**

操作：
1. 应用启动后，确保视图模式为 list（左上角图标为 `view_list`，如不是则切换）
2. 右键点击任一笔记卡片

预期：
- 在鼠标点击位置弹出菜单
- 菜单含「在新标签页打开」「删除」两项
- 「删除」项的图标和文字均为红色

- [ ] **步骤 3：验证桌面端 list 视图「新标签」功能**

操作：
1. 当前已有打开的笔记（活动标签页）
2. 右键另一篇笔记 → 点击「在新标签页打开」

预期：
- 新建一个标签页，内容为该笔记
- 标签页数量 +1，原活动标签页内容保持不变

- [ ] **步骤 4：验证桌面端 list 视图「删除」功能**

操作：
1. 右键某篇笔记 → 点击「删除」

预期：
- **无确认对话框**直接删除
- 该笔记从列表中消失
- 若该笔记已打开为标签页，对应标签页自动关闭

- [ ] **步骤 5：验证桌面端 waterfall 视图右键菜单**

操作：
1. 切换到 waterfall 视图（左上角点击切到 `grid_view`）
2. 右键任一笔记卡片

预期：菜单含「在新标签页打开」「删除」两项，「删除」为红色

- [ ] **步骤 6：验证桌面端菜单外部点击取消**

操作：右键弹出菜单后，点击菜单外任意位置

预期：菜单关闭，无任何副作用（笔记未被删除、未打开新标签）

- [ ] **步骤 7：验证回归 —— 现有删除路径仍带确认**

操作：
1. list 视图中，点击某笔记的 trailing 删除图标按钮
2. 在另一篇笔记上向左滑动触发 `Dismissible`

预期：两条路径**均仍弹出确认对话框**（与右键菜单的"直接删除"形成对比，验证无回归）

- [ ] **步骤 8：验证编辑器 PopupMenuButton 删除回归**

操作：打开某笔记，点击编辑器右上角的 PopupMenuButton →「删除」

预期：仍弹出确认对话框

- [ ] **步骤 9：验证移动端长按（如可在 Chrome 移动模拟器中测试）**

运行：`flutter run -d chrome`（或调试窗口宽度 ≤ 768）

操作：长按任一笔记卡片

预期：
- 弹出菜单，仅含「删除」一项（红色）
- 点击「删除」直接删除，无确认

- [ ] **步骤 10：验证最终代码无 analyzer 警告**

运行：`flutter analyze`
预期：无新增 error 或 warning（与基线一致）

---

## 自检结果

**规格覆盖度：** 设计文档每个章节均有任务对应：
- 「通用菜单方法」→ 任务 2
- 「删除逻辑重构」→ 任务 1
- 「视图集成 / list」→ 任务 3
- 「视图集成 / waterfall」→ 任务 4
- 「测试要点」→ 任务 5 步骤 2-10 逐项覆盖

**占位符扫描：** 无 TODO、无"类似任务 N"、无"添加适当错误处理"等模糊描述，每个代码步骤都给出完整代码块。

**类型一致性：**
- `_performDeleteNote(Note note)` 在任务 1 定义，任务 2 的 `_showNoteContextMenu`、任务 5 验证清单中均一致使用此签名
- `_showNoteContextMenu` 参数 `note / position / includeOpenInNewTab` 在任务 2 定义，任务 3、4 调用处完全匹配
- `details.globalPosition`（`Offset` 类型）在任务 3、4 中一致使用

**范围检查：** 单文件改动，5 个任务可一个会话完成，无进一步拆分必要。
