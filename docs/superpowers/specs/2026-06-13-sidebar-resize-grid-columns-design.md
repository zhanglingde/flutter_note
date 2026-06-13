# 侧边栏可拖动宽度 + 瀑布流动态列数

## 背景

当前桌面端笔记列表面板宽度固定为 320px，无法调整。瀑布流视图固定 2 列，不会根据面板宽度自适应。用户希望可以拖动调整列表面板宽度，并且瀑布流在宽度充足时展示更多列（最多 3 列）。

## 变更

### 1. 可拖动侧边栏分隔线

**位置**: `home_screen.dart` → `_buildDesktopLayout()`

**当前实现**:
```dart
SizedBox(width: 320, child: _buildNoteListPanel()),
const VerticalDivider(width: 1),
```

**新实现**:
- 新增状态变量 `double _sidebarWidth = 320`
- 将固定 `SizedBox(width: 320)` 改为 `SizedBox(width: _sidebarWidth)`
- 移除 `VerticalDivider`，替换为 6px 宽的拖动把手 `GestureDetector`
- 把手显示为细竖线，悬停时光标变为左右箭头

**拖动把手设计**:
- 宽度：6px，视觉上显示为 1px 的灰色细线（居中）
- 悬停/拖动时显示高亮色（`Theme.of(context).colorScheme.primary`）
- 光标：`SystemMouseCursors.resizeColumn`
- 拖动逻辑：`onPanUpdate` 更新 `_sidebarWidth`，clamp 在 200-500 范围

**约束**:
- 最小宽度：200px
- 最大宽度：500px
- 宽度不持久化，每次启动回到默认 320px

### 2. 瀑布流动态列数

**位置**: `home_screen.dart` → `_buildWaterfallView()`

**当前实现**:
```dart
crossAxisCount: 2,  // 固定 2 列
```

**新实现**:
- 使用 `LayoutBuilder` 获取列表面板实际宽度
- 动态计算：`crossAxisCount = min(3, max(2, (width / 180).floor()))`
  - 面板宽度 < 360px → 2 列
  - 面板宽度 >= 360px → 3 列
  - 上限 3 列

## 影响范围

- `lib/screens/home_screen.dart`：修改 `_buildDesktopLayout()` 和 `_buildWaterfallView()`
- 无新增依赖
- 无数据模型变更
- 仅影响桌面端布局，移动端不变
