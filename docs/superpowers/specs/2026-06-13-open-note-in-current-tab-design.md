# 点击笔记在当前标签页打开

## 背景

当前桌面端点击笔记列表中的笔记时，总是创建一个新标签页（除非该笔记已打开）。用户希望默认在当前活动标签页中打开笔记，避免标签页无限堆积。

## 变更

### 修改 `_openTab` 方法

**位置**: `lib/screens/home_screen.dart` → `_openTab()`（约 102-121 行）

**当前逻辑**:
1. 笔记已打开 → 切换到该标签页
2. 笔记未打开 → 新建标签页

**新逻辑**:
1. 笔记已打开 → 切换到该标签页（行为不变）
2. 笔记未打开，且有活动标签页（`_activeTabId != null`）→ **替换当前活动标签页的内容**
   - 先调用 `storageService.flushAutoSave()` 保存原笔记最新内容到数据库
   - 用 `TabState.copyWith(note: newNote)` 替换 `_tabs` 中活动标签页的内容
   - `copyWith` 保留原 `GlobalKey`，编辑器实例不变，重新加载新笔记内容
   - 更新 `lastAccessedAt`
3. 笔记未打开，且无标签页（`_tabs.isEmpty`）→ 新建第一个标签页（行为不变）

### `_createNote` 保持不变

点击 + 按钮时仍然新建标签页。这是用户明确的"创建新笔记"意图。

### `_onTabContentChanged` 处理

替换标签页内容后，`RichTextEditor` 会因为 `initialContent` 变化而重新加载。现有的 `_onTabContentChanged` 回调会处理新笔记的内容变更。

## 数据流

```
用户点击笔记
  ↓
_openNote(note)
  ↓
_openTab(note)
  ↓
笔记已打开? ── 是 ──→ 切换 _activeTabId（不变）
  │ 否
  ↓
_activeTabId != null? ── 否 ──→ 新建第一个标签页（不变）
  │ 是
  ↓
flushAutoSave() 保存原笔记
  ↓
_tabs[activeIndex] = activeTab.copyWith(note: note)
  ↓
_activeTabId 保持不变（已指向该 tab）
  ↓
setState 触发重建
```

## 影响范围

- `lib/screens/home_screen.dart`：修改 `_openTab()` 方法
- 无新增文件，无数据模型变更
- 移动端不受影响（仍通过 `Navigator.push` 打开新页面）
