# Markdown 支持规格

## ADDED Requirements

### Requirement: Markdown 语法输入
系统应当允许用户使用 Markdown 语法编写内容。

#### Scenario: 输入 markdown 语法
- **WHEN** 用户输入 markdown 语法（如 **粗体**、# 标题）
- **THEN** 文本以原始 markdown 格式存储

### Requirement: 实时预览
系统应当提供 Markdown 内容的实时预览。

#### Scenario: 移动端切换预览模式
- **WHEN** 用户在移动设备上点击预览切换按钮
- **THEN** 显示渲染后的 markdown 预览

#### Scenario: 桌面端分屏视图
- **WHEN** 用户在桌面/Web 查看 markdown 笔记
- **THEN** 编辑器和预览并排显示

#### Scenario: 预览实时更新
- **WHEN** 用户在编辑器中输入 markdown
- **THEN** 预览窗格更新显示渲染内容

### Requirement: 标准 Markdown 元素
系统应当支持常见 Markdown 元素。

#### Scenario: 渲染标题
- **WHEN** markdown 包含 # 标题 1
- **THEN** 预览渲染为 H1 标题

#### Scenario: 渲染粗体文本
- **WHEN** markdown 包含 **粗体文本**
- **THEN** 预览渲染为粗体文本

#### Scenario: 渲染斜体文本
- **WHEN** markdown 包含 *斜体文本*
- **THEN** 预览渲染为斜体文本

#### Scenario: 渲染链接
- **WHEN** markdown 包含 [链接文本](url)
- **THEN** 预览渲染为可点击的超链接

#### Scenario: 渲染代码块
- **WHEN** markdown 包含 ```代码```
- **THEN** 预览渲染为格式化的代码块

#### Scenario: 渲染列表
- **WHEN** markdown 包含 - 项目 或 1. 项目
- **THEN** 预览渲染为相应的列表类型

#### Scenario: 渲染引用块
- **WHEN** markdown 包含 > 引用
- **THEN** 预览渲染为引用块

### Requirement: Markdown 编辑工具栏
系统应当为常见 Markdown 语法提供辅助按钮。

#### Scenario: 插入标题语法
- **WHEN** 用户点击标题按钮
- **THEN** 在光标位置插入 #

#### Scenario: 插入链接语法
- **WHEN** 用户点击链接按钮
- **THEN** 插入 [文本](url) 模板

#### Scenario: 插入代码块语法
- **WHEN** 用户点击代码按钮
- **THEN** 插入 ```\ncode\n``` 模板

### Requirement: 滚动同步
系统应当在桌面上同步编辑器和预览之间的滚动。

#### Scenario: 同步编辑器滚动到预览
- **WHEN** 用户在编辑器窗格中滚动
- **THEN** 预览窗格滚动到相应位置

#### Scenario: 同步预览滚动到编辑器
- **WHEN** 用户在预览窗格中滚动
- **THEN** 编辑器窗格滚动到相应位置

### Requirement: 跨平台一致性
系统应当在 Android、Web 和 Windows 平台上提供一致的 Markdown 支持。

#### Scenario: Android 上 Markdown 渲染正常
- **WHEN** 用户在 Android 上创建 markdown 笔记
- **THEN** 预览正确显示所有支持的元素

#### Scenario: Web 上 Markdown 渲染正常
- **WHEN** 用户在 Web 浏览器中创建 markdown 笔记
- **THEN** 预览正确显示所有支持的元素

#### Scenario: Windows 上 Markdown 渲染正常
- **WHEN** 用户在 Windows 上创建 markdown 笔记
- **THEN** 预览正确显示所有支持的元素
