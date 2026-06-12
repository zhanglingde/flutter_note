## Why

当前笔记列表仅支持单一列表视图（`ListTile`），每条笔记占据一行、展示固定的标题+预览+日期。当笔记数量较多时，用户需要大量滚动才能浏览所有笔记，且无法快速通过视觉缩略识别笔记内容。提供瀑布流视图可以让笔记以卡片形式紧凑排列，利用横向空间提高浏览效率。

## What Changes

- 在左侧笔记列表面板顶部 AppBar 最左侧添加视图切换菜单按钮
- 支持两种视图模式：列表视图（现有）和瀑布流视图（新增）
- 瀑布流视图中每条笔记以卡片形式展示，包含标题、内容预览和日期
- 视图偏好需持久化，应用重启后保持上次选择的视图模式

## Capabilities

### New Capabilities
- `note-list-view-mode`: 笔记列表视图切换能力，包括列表视图和瀑布流视图两种展示模式，以及视图偏好的持久化存储

### Modified Capabilities

（无现有 spec 需要修改）

## Impact

- `lib/screens/home_screen.dart` — `_buildNoteListPanel()`、`_buildNoteListView()`、`_buildNoteCard()` 需要重构以支持多种视图
- 可能需要新增依赖包用于瀑布流布局（如 `flutter_staggered_grid_view`）
- 需要在 `_HomeScreenState` 中新增视图模式状态字段
- 视图偏好持久化可能涉及 `SharedPreferences` 或现有存储服务
