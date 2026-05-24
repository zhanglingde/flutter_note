# 富文本编辑器图片支持设计

## 目标

在富文本编辑器中支持粘贴剪贴板图片和选择本地图片文件。

## 存储方案

图片保存到文件系统，Delta 中存储文件路径。

- 保存路径：`{appDir}/images/{noteId}/{timestamp}.png`
- 笔记删除时批量清理对应图片目录

## 组件设计

### ImageStorageService

图片文件管理服务，职责：

- `saveImage(Uint8List bytes, String noteId)` → 保存图片，返回文件路径
- `deleteImagesForNote(String noteId)` → 删除笔记关联的所有图片
- `getImageFile(String path)` → 获取图片文件

### 剪贴板粘贴

在 RichTextEditor 中拦截粘贴事件：

1. 使用 `super_clipboard` 包读取剪贴板中的图片数据
2. 检测到图片 → 调用 ImageStorageService 保存到文件系统
3. 获取本地文件路径 → 在 Quill Delta 中插入 image embed

### Quill 图片渲染

flutter_quill 内置支持 image embed，传入本地文件路径即可渲染，无需自定义渲染器。

### 工具栏入口

在"段落"菜单中添加"图片"选项，调用文件选择器选择本地图片。

## 依赖

- `super_clipboard`：跨平台剪贴板图片读取
- `image_picker`（可选）：文件选择器

## 平台支持

| 平台 | 剪贴板粘贴 | 文件选择 |
|------|-----------|---------|
| Windows | 支持 | 支持 |
| Android | 支持 | 支持 |
| Web | 需要适配（文件系统改为 base64） | 支持 |
