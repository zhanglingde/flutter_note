## Context

当前应用在桌面端使用主从布局（master-detail）：左侧笔记列表 320px，右侧单个编辑器。点击列表中的笔记会替换编辑器内容，`_selectedNote` 只持有一个笔记引用。编辑器状态（滚动位置、光标、大纲展开）通过 `RichTextEditor` 的 `StatefulWidget` 本地状态管理，切换笔记时状态丢失。

移动端使用单列导航模式，通过 `Navigator.push` 打开编辑器，不在此次变更范围内。

## Goals / Non-Goals

**Goals:**
- 桌面端支持同时打开多个标签页，每个标签页对应一篇笔记
- 每个标签页独立维护编辑器状态（滚动位置、光标位置、大纲可见性）
- 标签页可关闭、可拖拽排序
- 点击已打开的笔记时切换到对应标签页而非打开新标签
- 标签过多时可横向滚动

**Non-Goals:**
- 移动端标签页支持（保持现有 Navigator.push 模式）
- 标签页状态持久化（应用重启后恢复打开的标签页）
- 分屏/并排编辑
- 标签页分组或颜色标记

## Decisions

### Decision 1: 标签页状态管理方式

**选择**: 在 `HomeScreen` 中使用 `Map<String, TabState>` 管理所有打开的标签页状态。

**理由**: 项目当前使用纯 `StatefulWidget` 本地状态，没有引入任何状态管理库。保持一致，避免为标签页引入新依赖。`TabState` 类封装每个标签页的笔记引用、`GlobalKey<RichTextEditorState>` 和滚动控制器。

**备选方案**:
- 引入 Provider/Riverpod — 过度设计，增加不必要的复杂度
- 使用 PageView + TabController — TabController 不支持独立状态管理，且不适合富文本编辑器场景

### Decision 2: 编辑器状态保持策略

**选择**: 使用 `IndexedStack` 或 `Offstage` 保持所有已打开标签页的编辑器 Widget 存活。

**理由**: `RichTextEditor` 的状态（QuillController、滚动位置、大纲状态）都存在 State 中。销毁再重建会导致状态丢失和性能问题。`Offstage` 比 `IndexedStack` 更节省资源（跳过布局和绘制），适合编辑器这种重量级 Widget。

**备选方案**:
- AutomaticKeepAliveClientMixin — 仅适用于 Scrollable 内部，不适用于此场景
- 手动序列化/反序列化状态 — 复杂度高，需要处理 Quill Delta 的各种细节

### Decision 3: 标签栏 UI 组件

**选择**: 自定义标签栏 Widget，基于 `ListView.builder` + `Draggable`/`DragTarget`。

**理由**: Material 的 `TabBar` 设计用于 `TabController` + `TabBarView` 联动，不适合自定义多实例编辑器场景。自建标签栏可以精确控制关闭按钮、拖拽、溢出滚动等行为。

### Decision 4: 标签页数量限制

**选择**: 最大 20 个标签页。超过时关闭最早未使用的标签页（LRU 策略）。

**理由**: 每个标签页持有一个完整的 `RichTextEditor` 实例，包括 QuillController 和可能的大型文档。不限制数量会导致内存问题。20 个标签页足够日常使用，同时在性能上可控。

## Risks / Trade-offs

- **[内存占用]** → 每个 `RichTextEditor` 实例消耗内存。限制最大 20 个标签页 + LRU 淘汰策略缓解。在实现后需要做内存测试。
- **[标签栏占用编辑空间]** → 标签栏高度固定 40px，对编辑区域影响较小。标签过多时通过水平滚动处理。
- **[与现有代码的兼容性]** → `_selectedNote` 的概念变为 `_activeTabId`，需要重构 `HomeScreen` 中大量依赖单个选中笔记的逻辑。影响范围可控，集中在 `home_screen.dart`。
