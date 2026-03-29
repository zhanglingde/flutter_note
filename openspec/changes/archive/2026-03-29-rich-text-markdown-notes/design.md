# Design: Rich Text & Markdown Notes

## Context

当前 Flutter 笔记应用是一个基础框架，仅包含入口文件，没有实际的笔记功能。需要构建一个完整的笔记应用，支持富文本编辑和 Markdown 两种模式。

**约束条件**:
- 必须支持 Android、Web、Windows 三个平台
- 使用 Flutter SDK ^3.11.0
- 需要本地持久化，不依赖云端服务
- 单用户应用，无需认证系统

**技术栈选择考虑**:
- Flutter 提供跨平台能力
- 需要成熟的富文本编辑器组件
- 需要可靠的本地存储方案

## Goals / Non-Goals

**Goals:**
- 实现功能完整的富文本编辑器，支持常见格式化操作
- 实现 Markdown 编辑器，支持实时预览
- 实现笔记的 CRUD 操作和本地持久化
- 提供流畅的编辑模式切换体验
- 确保三个平台（Android、Web、Windows）功能一致

**Non-Goals:**
- 云端同步功能（未来考虑）
- 多用户协作功能
- 富文本与 Markdown 的完美双向转换（技术限制）
- 图片、附件存储（首版不包含）
- 笔记分类、标签系统（首版不包含）

## Decisions

### 1. 富文本编辑器选择: flutter_quill

**决策**: 使用 `flutter_quill` 作为富文本编辑器

**理由**:
- 成熟度高，社区活跃，维护良好
- 跨平台支持好（Android、iOS、Web、Desktop）
- 提供完整的格式化工具栏
- 支持 Delta 格式，便于序列化和存储
- 可扩展性强

**替代方案考虑**:
- `zefyr`: 不再维护，基于旧的 Quill 架构
- `flutter_summernote`: 仅支持 Web 和 Android
- 自定义实现: 开发成本高，稳定性难以保证

### 2. Markdown 编辑器选择: flutter_markdown + TextField

**决策**: 使用 `flutter_markdown` 渲染预览，配合标准 `TextField` 进行编辑

**理由**:
- `flutter_markdown` 是官方推荐的 Markdown 渲染库
- 分离编辑和预览，实现简单清晰
- 可以实现实时预览或分屏预览

**替代方案考虑**:
- `flutter_markdown_editor`: 功能有限，不够灵活
- `flutter_quill` 的 Markdown 模式: 转换不完美，可能有格式丢失

### 3. 本地存储方案: Hive

**决策**: 使用 `Hive` 作为本地存储方案

**理由**:
- 纯 Dart 实现，跨平台一致性最好
- 性能优秀（比 SQLite 快）
- 无需原生依赖，Web 支持好
- 支持加密（未来可用）
- API 简单，学习成本低

**替代方案考虑**:
- `shared_preferences`: 仅适合简单键值存储，不适合大量笔记
- `sqflite`: Web 支持需要额外配置，相对复杂
- `isar`: 功能强大但相对较新，包体积较大

### 4. 数据模型设计

**决策**: 笔记数据模型包含两种格式

```dart
class Note {
  String id;              // 唯一标识
  String title;           // 标题
  DateTime createdAt;     // 创建时间
  DateTime updatedAt;     // 更新时间
  NoteType type;          // rich_text | markdown
  String content;         // 内容（Delta JSON 或 Markdown 文本）
}
```

**理由**:
- 使用 `type` 字段区分编辑模式
- 富文本内容存储为 Quill Delta JSON 格式
- Markdown 内容存储为纯文本
- 不做双向转换，避免格式丢失

**权衡**:
- ❌ 无法在两种模式间完美切换
- ✅ 保证各自模式的格式完整性
- ✅ 实现简单，数据一致性高

### 5. 应用架构: 简单分层架构

**决策**: 采用简单的三层架构

```
lib/
├── main.dart                 # 应用入口
├── models/
│   └── note.dart            # 数据模型
├── services/
│   └── note_storage_service.dart  # 存储服务
├── screens/
│   ├── home_screen.dart     # 笔记列表页
│   └── editor_screen.dart   # 编辑器页
└── widgets/
    ├── rich_text_editor.dart    # 富文本编辑器组件
    └── markdown_editor.dart     # Markdown 编辑器组件
```

**理由**:
- 首版功能简单，不需要复杂架构
- 便于快速开发和迭代
- 清晰的关注点分离

**替代方案考虑**:
- BLoC/Cubit: 对于简单应用过于复杂
- Provider + MVVM: 可以考虑，但首版不需要
- Riverpod: 学习曲线相对较陡

### 6. UI 设计策略

**决策**: 采用 Material Design 3，简洁实用

**核心界面**:
1. **首页**: 笔记列表 + 新建按钮
2. **编辑页**: 顶部工具栏 + 编辑区域 + 模式切换按钮

**交互设计**:
- 首次创建笔记时选择编辑模式（富文本或 Markdown）
- 创建后模式固定，避免格式转换问题
- Markdown 模式提供实时预览开关

## Risks / Trade-offs

### Risk 1: flutter_quill 在 Web 平台的兼容性
**风险**: flutter_quill 在 Web 平台可能有性能或兼容性问题
**缓解措施**:
- 提前在 Web 平台测试核心功能
- 准备降级方案（纯文本编辑）
- 关注官方 issue 和更新

### Risk 2: 数据迁移和版本兼容
**风险**: 未来版本更新可能导致数据格式不兼容
**缓解措施**:
- 在数据模型中包含版本号
- 实现数据迁移逻辑
- 定期备份机制

### Risk 3: Hive 的 Web 存储限制
**风险**: Web 平台使用 IndexedDB，可能有存储大小限制
**缓解措施**:
- 监控存储使用情况
- 提供数据导出功能
- 限制单个笔记大小

### Trade-off 1: 不支持模式互转
**权衡**: 为了保证格式完整性，不支持富文本和 Markdown 的相互转换
**影响**: 用户需要在一开始选择合适的编辑模式

### Trade-off 2: 首版功能简化
**权衡**: 不包含图片、标签、分类等高级功能
**影响**: 产品功能相对基础，但可快速上线验证核心需求

## Migration Plan

**阶段 1: 基础架构** (1-2 天)
- 搭建项目结构
- 集成依赖包
- 实现数据模型和存储服务

**阶段 2: 核心功能** (3-4 天)
- 实现笔记列表页
- 实现富文本编辑器
- 实现 Markdown 编辑器
- 实现笔记 CRUD

**阶段 3: 优化和测试** (1-2 天)
- 三平台测试
- UI/UX 优化
- 性能优化

**回滚策略**:
- 使用 Hive 的 box 备份功能
- 提供数据导出功能（JSON 格式）
- 版本控制管理代码

## Open Questions

1. **Markdown 实时预览方式**: 分屏预览还是切换预览？
   - 建议：移动端使用切换预览，桌面/Web 使用分屏预览

2. **笔记自动保存策略**: 实时保存还是定时保存？
   - 建议：文本变化后延迟 1-2 秒自动保存

3. **删除笔记的处理**: 直接删除还是回收站机制？
   - 建议：首版使用直接删除，未来添加回收站

4. **笔记排序方式**: 按创建时间还是更新时间？
   - 建议：默认按更新时间降序，未来可支持用户选择
