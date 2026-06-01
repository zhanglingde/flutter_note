## 1. 依赖和配置

- [x] 1.1 在 `pubspec.yaml` 中添加 `sqflite` 和 `sqflite_common_ffi` 依赖
- [x] 1.2 在 `pubspec.yaml` 中移除 `hive` 和 `hive_flutter` 依赖
- [x] 1.3 运行 `flutter pub get` 验证依赖

## 2. 数据模型修改

- [x] 2.1 修改 `Note` 类：移除 `HiveObject` 继承、`@HiveType`/`@HiveField` 注解、`part 'note.g.dart'`
- [x] 2.2 删除 `lib/models/note.g.dart` 文件
- [x] 2.3 在 `Note` 类中添加 `toMap()`/`fromMap()` 方法用于 SQLite 交互

## 3. NoteStorageService 重写

- [x] 3.1 重写 `init()` 方法：初始化 SQLite 数据库（Android 用 `sqflite`，Windows 用 `sqflite_common_ffi`），创建 `notes` 表和索引
- [x] 3.2 重写 `saveNote()`：使用 `INSERT OR REPLACE` SQL 语句
- [x] 3.3 重写 `loadNotes()`：使用 `SELECT * FROM notes` 查询
- [x] 3.4 重写 `loadNoteById()`：使用 `SELECT` 带 `WHERE id = ?` 查询
- [x] 3.5 重写 `deleteNote()`：使用 `DELETE FROM notes WHERE id = ?`
- [x] 3.6 重写 `searchNotes()`：使用 `SELECT` 带 `LIKE` 查询
- [x] 3.7 重写 `loadNotesSortedByUpdatedAt()`：使用 `ORDER BY updated_at DESC`
- [x] 3.8 保持 `scheduleAutoSave()` 和 `flushAutoSave()` 防抖逻辑不变
- [x] 3.9 重写 `close()`：关闭 SQLite 数据库连接

## 4. Hive 到 SQLite 数据迁移

- [x] 4.1 在 `init()` 中添加迁移检测：检查 SQLite 中是否存在迁移标记
- [x] 4.2 实现迁移逻辑：接受 Hive JSON 数据列表 → 批量插入 SQLite → 写入迁移标记
- [x] 4.3 迁移完成后写入标记，后续启动跳过迁移

## 5. 初始化流程更新

- [x] 5.1 修改 `main.dart`：移除 `Hive.initFlutter()`，改为初始化 `NoteStorageService`（内部处理 SQLite 初始化）
- [x] 5.2 添加应用退出时的数据库关闭逻辑

## 6. 清理 Hive 相关代码

- [x] 6.1 确认所有 `import 'package:hive` 引用已移除
- [x] 6.2 确认 `note.g.dart` 已删除且无引用

## 7. 验证

- [x] 7.1 运行 `flutter analyze` 确保无静态分析错误
- [ ] 7.2 运行 `flutter run -d windows` 验证 Windows 平台正常
- [ ] 7.3 测试创建、编辑、删除笔记功能正常
- [ ] 7.4 测试自动保存和退出保存正常
- [ ] 7.5 测试搜索功能正常
- [ ] 7.6 测试已有 Hive 数据迁移到 SQLite 正常
