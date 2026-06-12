## Context

当前 `HomeScreen` 的左侧笔记列表面板 (`_buildNoteListPanel`) 使用固定 320px 宽的 `ListView.builder`，每条笔记渲染为一个 `ListTile`（标题+预览+日期）。面板顶部是 `AppBar`，含标题"笔记"和一个搜索按钮。没有任何视图切换机制。

用户希望在列表视图之外增加瀑布流视图，通过顶部菜单切换。

## Goals / Non-Goals

**Goals:**
- 在 AppBar 最左侧添加视图切换按钮（PopupMenuButton 或 IconButton + PopupMenu）
- 实现瀑布流视图，每条笔记以卡片形式展示，高度根据内容自适应
- 视图偏好持久化，重启后恢复

**Non-Goals:**
- 不支持自定义列数（固定为 2 列）
- 不支持拖拽排序
- 不支持卡片缩略图/封面图
- 不涉及移动端布局改动（仅桌面端左侧面板）

## Decisions

### 1. 瀑布流布局：使用 `flutter_staggered_grid_view`

**选择**: `MasonryGridView.builder`

**备选**:
- `Wrap` — 不支持真正的瀑布流（高度不一致的交叉列布局）
- `GridView.extent` — 固定行高，无法实现瀑布流效果
- 自定义 Sliver — 开发成本高

**理由**: `flutter_staggered_grid_view` 是 Flutter 生态最成熟的瀑布流方案，`MasonryGridView` 能自动处理不同高度的子项，与现有 `ListView.builder` 的 itemBuilder 模式一致。

### 2. 视图切换控件：PopupMenuButton

**选择**: 在 AppBar 的 `leading` 位置放置 `PopupMenuButton`，图标随当前视图模式变化（列表用 `Icons.view_list`，瀑布流用 `Icons.grid_view`）。

**备选**:
- SegmentedControl — 占用 AppBar 空间过多
- 独立 IconButtons — 不够直观

**理由**: PopupMenuButton 扩展性好（未来可加更多视图模式），图标本身也是视觉指示器。

### 3. 视图偏好持久化：SharedPreferences

**选择**: 新增 `shared_preferences` 依赖，存储 key `note_list_view_mode`。

**备选**:
- SQLite 单独表 — 过重，仅为一个布尔偏好
- 内存态 — 重启丢失

**理由**: SharedPreferences 是 Flutter 标准 key-value 持久化方案，适合简单配置项。

### 4. 瀑布流卡片设计

卡片内容：标题（最多 2 行）+ 内容预览（最多 4 行，提供更多上下文）+ 日期。卡片有圆角和边框，选中态高亮。卡片宽度由列数自动决定，高度自适应内容。

## Risks / Trade-offs

- [320px 面板宽度下 2 列瀑布流可能显得拥挤] → 减小卡片内边距和字体，确保标题和预览可读
- [新增 `flutter_staggered_grid_view` 和 `shared_preferences` 两个依赖] → 都是成熟稳定包，维护活跃
- [切换视图时的滚动位置丢失] → 接受此限制，不做滚动位置保持（笔记按更新时间排序，首项固定）
