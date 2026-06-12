## 1. 依赖安装

- [x] 1.1 在 `pubspec.yaml` 中添加 `flutter_staggered_grid_view` 依赖
- [x] 1.2 在 `pubspec.yaml` 中添加 `shared_preferences` 依赖
- [x] 1.3 运行 `flutter pub get` 验证依赖安装

## 2. 视图模式状态管理

- [x] 2.1 在 `_HomeScreenState` 中添加 `_viewMode` 枚举字段（`list` / `waterfall`），默认 `list`
- [x] 2.2 在 `initState` 中从 SharedPreferences 加载 `_viewMode`
- [x] 2.3 添加 `_setViewMode` 方法，更新状态并持久化到 SharedPreferences

## 3. 视图切换按钮

- [x] 3.1 在 `_buildNoteListPanel` 的 AppBar 中设置 `leading` 为 `PopupMenuButton`，图标根据 `_viewMode` 变化
- [x] 3.2 PopupMenu 提供"列表视图"和"瀑布流视图"两个选项，当前模式显示勾选标记

## 4. 瀑布流视图实现

- [x] 4.1 重构 `_buildNoteListView`：根据 `_viewMode` 返回列表视图或瀑布流视图
- [x] 4.2 实现 `_buildWaterfallView` 方法，使用 `MasonryGridView.builder`（2 列）
- [x] 4.3 实现 `_buildNoteCard` 瀑布流卡片组件（标题 2 行 + 预览 4 行 + 日期，圆角边框，选中高亮）

## 5. 验证

- [x] 5.1 运行 `flutter analyze` 确认无警告
- [ ] 5.2 在 Windows 桌面端手动验证：列表视图正常、切换到瀑布流视图正常、视图偏好持久化
