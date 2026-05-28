## 1. 移除旧实现

- [x] 1.1 移除 `_buildCodeBlockToolbar()` 方法及其在 `build()` 中的调用
- [x] 1.2 移除 `_cursorInCodeBlock`、`_currentCodeBlockLang`、`_currentCodeBlockOffset` 等光标追踪状态变量
- [x] 1.3 移除 `_detectCodeBlockCursor()` 方法及相关调用

## 2. 修复语言持久化

- [x] 2.1 审查 `_loadCodeBlockLanguages()` 恢复逻辑，确保从 delta 属性中正确读取 `code-block-lang`
- [x] 2.2 审查 `_persistCodeBlockLang()` 写入逻辑，验证 compose 操作正确写入 delta
- [ ] 2.3 测试：创建代码块 → 选择语言 → 保存 → 重新打开，验证语言恢复

## 3. 实现代码块 header

- [x] 3.1 在 `_buildLeadingBlock` 中为代码块第一行构建 header widget（语言标签 + 复制按钮）
- [x] 3.2 header 语言标签点击弹出语言选择菜单（复用 `_showLanguagePicker` 逻辑，锚定到标签位置）
- [x] 3.3 header 复制按钮点击复制对应代码块内容（复用 `_copyCurrentCodeBlock` 逻辑，按 block offset 查找）
- [x] 3.4 移除原 leading pill 的语言标签渲染，仅在第一行渲染 header

## 4. 视觉样式

- [x] 4.1 header 使用与代码块一致的深色背景色系
- [x] 4.2 header 左侧显示大写语言名称（如 "DART"）+ 下拉箭头图标
- [x] 4.3 header 右侧显示复制图标
- [x] 4.4 header 与代码块内容区域之间无间距

## 5. 验证

- [x] 5.1 运行 `flutter analyze` 确保无静态分析错误
- [ ] 5.2 运行应用，验证代码块 header 正确显示
- [ ] 5.3 验证语言切换后持久化正常
- [ ] 5.4 验证复制功能正常
- [ ] 5.5 验证主工具栏下方不再显示代码块工具条
