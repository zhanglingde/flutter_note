# 点击笔记在当前标签页打开 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 桌面端点击笔记列表时，在当前活动标签页中替换内容打开笔记，而非总是新建标签页。

**架构：** 修改 `_openTab` 方法，新增"替换活动标签页"分支：当笔记未打开且有活动标签页时，先 `flushAutoSave` 保存原笔记，再用 `TabState.copyWith(note:)` 原地替换内容（保留 GlobalKey 以复用编辑器实例）。

**技术栈：** Flutter，无新增依赖。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `lib/screens/home_screen.dart` | 修改 `_openTab()`（改为 async + 替换逻辑）、`_openNote`（await `_openTab`） |

无新增文件，无数据模型变更。

---

## 任务 1：修改 `_openTab` 支持替换当前标签页

**文件：**
- 修改：`lib/screens/home_screen.dart:102-121`（`_openTab` 方法）
- 修改：`lib/screens/home_screen.dart:267-283`（`_openNote` 方法）

- [ ] **步骤 1：将 `_openTab` 改为 `async` 并新增替换分支**

将 `lib/screens/home_screen.dart:102-121` 的 `_openTab` 方法替换为：

```dart
  Future<void> _openTab(Note note) async {
    final existingIndex = _tabs.indexWhere((t) => t.id == note.id);
    if (existingIndex >= 0) {
      // 已打开 -> 切换并更新访问时间
      setState(() {
        _activeTabId = note.id;
        _tabs[existingIndex] = _tabs[existingIndex]
            .copyWith(lastAccessedAt: DateTime.now());
      });
    } else if (_activeTabId != null) {
      // 未打开但有活动标签页 -> 替换当前标签页内容
      // 先保存原笔记的最新内容到数据库
      await widget.storageService.flushAutoSave();
      final activeIndex = _tabs.indexWhere((t) => t.id == _activeTabId);
      if (activeIndex < 0) return;
      setState(() {
        _tabs[activeIndex] = _tabs[activeIndex]
            .copyWith(note: note, lastAccessedAt: DateTime.now());
        _activeTabId = note.id;
      });
    } else {
      // 无标签页 -> 新建第一个标签页
      if (_tabs.length >= _maxTabs) {
        _evictOldestTab();
      }
      setState(() {
        _tabs.add(TabState(note: note, key: GlobalKey()));
        _activeTabId = note.id;
      });
    }
  }
```

- [ ] **步骤 2：在 `_openNote` 中 `await _openTab`**

将 `lib/screens/home_screen.dart` 中 `_openNote` 方法里的 `_openTab(note)` 调用改为 `await`：

```dart
  Future<void> _openNote(Note note) async {
    final isDesktop = MediaQuery.of(context).size.width > 768;
    if (isDesktop) {
      await _openTab(note);
    } else {
      // ... 移动端逻辑不变
    }
  }
```

（仅修改桌面端分支，在 `_openTab(note)` 前加 `await`）

- [ ] **步骤 3：运行 `flutter analyze` 验证无 error**

运行：`flutter analyze lib/screens/home_screen.dart`
预期：无 error（可能存在已有的 info/warning，忽略）

- [ ] **步骤 4：Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: 点击笔记默认在当前标签页打开而非新建标签页"
```

---

## 任务 2：手动验证

**文件：** 无代码改动，运行时验证

- [ ] **步骤 1：启动 Windows 桌面应用**

运行：`flutter run -d windows`

- [ ] **步骤 2：验证替换当前标签页**

操作：
1. 应用启动后，若已有打开的笔记，活动标签页显示该笔记
2. 点击侧边栏列表中另一篇笔记
3. 确认当前标签页内容被替换为新笔记，标签页数量不变

预期：标签页总数不变，活动标签页内容切换为新笔记。

- [ ] **步骤 3：验证原笔记自动保存**

操作：
1. 在笔记 A 中输入未保存的修改
2. 不等待 2 秒自动保存，立即点击笔记 B
3. 等待几秒后切回笔记 A（此时会在当前标签页替换）

预期：笔记 A 的修改已持久化（重新打开仍能看到）。

- [ ] **步骤 4：验证空状态新建标签页**

操作：
1. 关闭所有标签页（此时显示空状态"选择或创建一个笔记"）
2. 点击侧边栏任一笔记

预期：新建第一个标签页，内容为该笔记。

- [ ] **步骤 5：验证已打开笔记切换不变**

操作：打开笔记 A（标签页 1），再创建新笔记（+ 按钮，标签页 2），点击侧边栏笔记 A

预期：切换到标签页 1（笔记 A），不替换标签页 2 内容，标签页数量不变。

- [ ] **步骤 6：验证创建笔记仍新建标签页**

操作：点击 + 按钮创建笔记

预期：新建标签页（不受"替换当前"逻辑影响）。
