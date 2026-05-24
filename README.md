# Note - Flutter 笔记应用

一个支持富文本和 Markdown 的跨平台笔记应用。

## 功能特性

- **富文本编辑器**
  - 文本格式化（粗体、斜体、下划线、删除线）
  - 对齐方式（左对齐、居中、右对齐、两端对齐）
  - 标题级别（H1、H2、H3）
  - 有序列表和无序列表
  - 撤销/重做功能
  - **Markdown 自动转换**：输入 Markdown 语法后自动转换为富文本格式
    - 标题：`# 标题` → H1, `## 标题` → H2, `### 标题` → H3
    - 粗体：`**文本**` → **文本**
    - 斜体：`*文本*` → *文本*
    - 删除线：`~~文本~~` → ~~文本~~
    - 行内代码：`` `代码` `` → 代码格式
    - 无序列表：`- 项目` → 列表项
    - 有序列表：`1. 项目` → 列表项
    - 可通过工具栏按钮开关此功能

- **Markdown 编辑器**
  - 实时预览（桌面端分屏，移动端切换）
  - 工具栏快捷插入
  - 支持 GitHub 风格 Markdown
  - 滚动同步（桌面端）

- **笔记管理**
  - 创建、编辑、删除笔记
  - 自动保存（2秒延迟）
  - 笔记搜索
  - 笔记复制

- **跨平台支持**
  - Windows 桌面
  - Android
  - Web 浏览器

## 技术栈

- **Flutter SDK**: ^3.11.0
- **富文本编辑器**: flutter_quill
- **Markdown 渲染**: flutter_markdown
- **本地存储**: Hive

## 快速开始

### 安装依赖

```bash
flutter pub get
```

### 运行应用

```bash
# Windows
flutter run -d windows

# Web
flutter run -d chrome

# Android（需连接设备或启动模拟器）
flutter run -d android
```

### 构建生产版本

```bash
# Windows
flutter build windows

# Web
flutter build web

# Android
flutter build apk
```

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── models/
│   └── note.dart               # 笔记数据模型
├── services/
│   └── note_storage_service.dart  # 存储服务
├── screens/
│   ├── home_screen.dart        # 首页（笔记列表）
│   └── editor_screen.dart      # 编辑器页面
└── widgets/
    ├── rich_text_editor.dart   # 富文本编辑器组件
    └── markdown_editor.dart    # Markdown 编辑器组件
```

## 使用说明

### 创建笔记

1. 点击首页右下角的 "+" 按钮
2. 选择笔记类型（富文本或 Markdown）
3. 开始编辑

### 编辑笔记

- **富文本模式**: 使用工具栏按钮进行格式化
- **Markdown 模式**:
  - 桌面端：左侧编辑，右侧实时预览
  - 移动端：点击底部按钮切换编辑/预览

### 删除笔记

- 在首页滑动笔记卡片
- 或在编辑页面点击菜单 → 删除

## 代码规范

- 遵循 Flutter/Dart 编码规范
- 使用 `flutter_lints` 包的 lint 规则
- 保持组件小而专注
- 尽可能使用 const 构造函数

## 许可证

MIT License
