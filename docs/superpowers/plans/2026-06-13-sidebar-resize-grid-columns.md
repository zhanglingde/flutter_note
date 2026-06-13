# 侧边栏可拖动宽度 + 瀑布流动态列数 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 桌面端笔记列表面板宽度可拖动调整，瀑布流视图根据面板宽度动态展示 2-3 列。

**架构：** 在 `_HomeScreenState` 中新增 `double _sidebarWidth` 状态变量驱动侧边栏宽度；用 6px 宽的 `MouseRegion` + `GestureDetector` 拖动把手替换 `VerticalDivider`；瀑布流用 `LayoutBuilder` 获取面板宽度后动态计算 `crossAxisCount`（上限 3）。

**技术栈：** Flutter，无新增依赖。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `lib/screens/home_screen.dart` | 修改 `_HomeScreenState`（新增 `_sidebarWidth` 字段）、`_buildDesktopLayout()`（可拖动把手）、`_buildWaterfallView()`（动态列数） |

无新增文件，无新增依赖。

---

## 任务 1：新增侧边栏宽度状态变量与拖动把手

**文件：**
- 修改：`lib/screens/home_screen.dart`（`_HomeScreenState` 类字段区，约第 30 行附近）
- 修改：`lib/screens/home_screen.dart:367-391`（`_buildDesktopLayout()`）

- [ ] **步骤 1：在 `_HomeScreenState` 中新增 `_sidebarWidth` 状态变量**

找到 `_HomeScreenState` 类中已有字段声明区域（例如 `NoteListViewMode _viewMode` 附近），新增字段：

```dart
double _sidebarWidth = 320;
```

- [ ] **步骤 2：替换 `_buildDesktopLayout()` 中的固定宽度与分隔线**

将 `lib/screens/home_screen.dart:367-391` 的 `_buildDesktopLayout()` 方法体替换为：

```dart
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // 左侧：笔记列表面板（宽度可拖动）
          SizedBox(
            width: _sidebarWidth,
            child: _buildNoteListPanel(),
          ),
          // 可拖动分隔线
          _buildSidebarResizer(),
          // 右侧：标签栏 + 编辑器面板
          Expanded(
            child: _tabs.isEmpty
                ? _buildEmptyEditorPanel()
                : _buildEditorPanelWithTabs(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        child: const Icon(Icons.add),
      ),
    );
  }
```

- [ ] **步骤 3：新增 `_buildSidebarResizer()` 拖动把手方法**

在 `_buildDesktopLayout()` 方法之后新增方法：

```dart
  /// 侧边栏可拖动分隔线
  Widget _buildSidebarResizer() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            _sidebarWidth = (_sidebarWidth + details.delta.dx)
                .clamp(200.0, 500.0);
          });
        },
        onHorizontalDragUpdate: (details) {
          setState(() {
            _sidebarWidth = (_sidebarWidth + details.delta.dx)
                .clamp(200.0, 500.0);
          });
        },
        child: Container(
          width: 6,
          color: Theme.of(context).dividerColor,
        ),
      ),
    );
  }
```

- [ ] **步骤 4：运行 `flutter analyze` 验证无 error**

运行：`flutter analyze lib/screens/home_screen.dart`
预期：无 error（可能存在已有的 info/warning，忽略）

- [ ] **步骤 5：Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: 桌面端笔记列表面板支持拖动调整宽度"
```

---

## 任务 2：瀑布流视图动态列数（最多 3 列）

**文件：**
- 修改：`lib/screens/home_screen.dart:862-875`（`_buildWaterfallView()`）

- [ ] **步骤 1：在文件顶部确认 `dart:math` 已导入（`min`/`max` 需要）**

在 `lib/screens/home_screen.dart` 顶部 import 区，确认是否已导入 `dart:math`。如果没有，添加：

```dart
import 'dart:math' show min, max;
```

- [ ] **步骤 2：替换 `_buildWaterfallView()` 方法体，用 `LayoutBuilder` 动态计算列数**

将 `lib/screens/home_screen.dart:862-875` 的 `_buildWaterfallView()` 方法替换为：

```dart
  Widget _buildWaterfallView(List<Note> notes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据面板宽度动态计算列数，上限 3 列
        // 每列至少 180px，最少 2 列，最多 3 列
        final crossAxisCount = min(
          3,
          max(2, (constraints.maxWidth / 180).floor()),
        );
        return MasonryGridView.builder(
          itemCount: notes.length,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
          ),
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            return _buildWaterfallCard(notes[index]);
          },
        );
      },
    );
  }
```

- [ ] **步骤 3：运行 `flutter analyze` 验证无 error**

运行：`flutter analyze lib/screens/home_screen.dart`
预期：无 error

- [ ] **步骤 4：Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: 瀑布流视图根据面板宽度动态展示 2-3 列"
```

---

## 任务 3：手动验证

**文件：** 无代码改动，运行时验证

- [ ] **步骤 1：启动 Windows 桌面应用**

运行：`flutter run -d windows`

- [ ] **步骤 2：验证拖动把手**

操作：
1. 鼠标悬停在侧边栏和编辑器之间的分隔线上
2. 确认光标变为左右箭头（`resizeColumn`）
3. 按住拖动，确认侧边栏宽度实时变化
4. 拖到最左，确认宽度不低于 200px
5. 拖到最右，确认宽度不超过 500px

预期：分隔线可拖动，宽度在 200-500px 范围内实时变化。

- [ ] **步骤 3：验证瀑布流动列数**

操作：
1. 点击侧边栏视图切换按钮，切换到瀑布流视图
2. 拖动侧边栏到最窄（约 200px），确认瀑布流显示 2 列
3. 拖动侧边栏到较宽（≥360px），确认瀑布流显示 3 列
4. 确认列数不会超过 3 列

预期：面板宽度 < 360px 时 2 列，≥ 360px 时 3 列，上限 3 列。

- [ ] **步骤 4：验证移动端不受影响**

操作：将窗口缩小到宽度 ≤ 768px（触发移动端布局）

预期：不显示侧边栏拖动把手，使用移动端单栏布局，无回归。
