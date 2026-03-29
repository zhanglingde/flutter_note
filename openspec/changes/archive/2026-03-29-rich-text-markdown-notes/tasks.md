# 实现任务清单

## 1. 项目设置与依赖

- [x] 1.1 添加依赖包到 pubspec.yaml (flutter_quill, flutter_markdown, hive, path_provider)
- [x] 1.2 创建项目目录结构 (models, services, screens, widgets)
- [x] 1.3 配置 Hive 初始化
- [x] 1.4 创建 Note 数据模型 (id, title, content, type, createdAt, updatedAt)

## 2. 存储层实现

- [x] 2.1 实现 NoteStorageService 基础类
- [x] 2.2 实现笔记保存功能 (saveNote)
- [x] 2.3 实现笔记加载功能 (loadNotes, loadNoteById)
- [x] 2.4 实现笔记删除功能 (deleteNote)
- [x] 2.5 实现笔记搜索功能 (searchNotes)
- [x] 2.6 添加自动保存逻辑 (2秒延迟)

## 3. 富文本编辑器实现

- [x] 3.1 创建 RichTextEditor 组件基础结构
- [x] 3.2 集成 flutter_quill 编辑器
- [x] 3.3 实现格式化工具栏 (粗体、斜体、下划线、删除线)
- [x] 3.4 实现对齐工具栏 (左对齐、居中、右对齐、两端对齐)
- [x] 3.5 实现标题选择器 (H1, H2, H3)
- [x] 3.6 实现列表功能 (有序列表、无序列表)
- [x] 3.7 实现撤销/重做功能
- [x] 3.8 实现 Quill Delta 到 JSON 的序列化

## 4. Markdown 编辑器实现

- [x] 4.1 创建 MarkdownEditor 组件基础结构
- [x] 4.2 实现 Markdown 文本输入区域
- [x] 4.3 集成 flutter_markdown 预览渲染
- [x] 4.4 实现移动端预览切换按钮
- [x] 4.5 实现桌面端分屏视图 (编辑器 + 预览)
- [x] 4.6 实现 Markdown 工具栏 (标题、链接、代码块)
- [x] 4.7 实现编辑器和预览的滚动同步 (桌面端)
- [x] 4.8 支持标准 Markdown 元素 (标题、粗体、斜体、链接、代码、列表、引用)

## 5. 笔记管理界面

- [x] 5.1 创建 HomeScreen 基础结构
- [x] 5.2 实现笔记列表视图 (ListView)
- [x] 5.3 实现笔记卡片组件 (标题、预览、时间戳、类型指示器)
- [x] 5.4 实现笔记排序 (按 updatedAt 降序)
- [x] 5.5 实现创建笔记按钮和类型选择对话框
- [x] 5.6 实现笔记删除功能 (滑动删除或长按菜单)
- [x] 5.7 实现删除确认对话框
- [x] 5.8 实现笔记搜索功能 (搜索栏 + 过滤逻辑)
- [x] 5.9 实现空状态显示 (无笔记时的提示)

## 6. 编辑器界面

- [x] 6.1 创建 EditorScreen 基础结构
- [x] 6.2 实现根据笔记类型加载对应编辑器
- [x] 6.3 实现自动标题提取 (从首行)
- [x] 6.4 实现自动保存触发
- [x] 6.5 实现返回时保存检查
- [x] 6.6 实现编辑器顶部工具栏
- [x] 6.7 处理空笔记的标题显示 ("无标题")

## 7. 应用入口与导航

- [x] 7.1 更新 main.dart 应用入口
- [x] 7.2 实现应用主题配置 (Material Design 3)
- [x] 7.3 实现路由导航 (HomeScreen ↔ EditorScreen)
- [x] 7.4 添加应用标题和图标

## 8. 平台适配与优化

- [ ] 8.1 测试 Android 平台功能
- [ ] 8.2 测试 Web 平台功能 (IndexedDB 存储)
- [ ] 8.3 测试 Windows 平台功能
- [x] 8.4 优化列表加载性能 (100+ 笔记)
- [x] 8.5 优化大笔记存储 (10,000+ 字符)
- [x] 8.6 添加存储错误处理和用户提示

## 9. 测试与调试

- [x] 9.1 编写 Note 模型单元测试
- [x] 9.2 编写 NoteStorageService 单元测试
- [ ] 9.3 测试富文本编辑器所有格式化功能
- [ ] 9.4 测试 Markdown 编辑器所有语法元素
- [ ] 9.5 测试笔记 CRUD 操作
- [ ] 9.6 测试搜索功能
- [ ] 9.7 测试自动保存机制
- [ ] 9.8 测试跨平台数据一致性

## 10. 文档与收尾

- [x] 10.1 更新 README.md 使用说明
- [x] 10.2 添加代码注释
- [x] 10.3 进行代码格式化 (flutter format)
- [x] 10.4 运行静态分析 (flutter analyze)
- [x] 10.5 准备发布构建 (flutter build)
