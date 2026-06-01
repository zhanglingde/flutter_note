import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
export 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;
import 'package:path/path.dart' as p;
import '../models/note.dart';

/// 存储操作结果
class StorageResult<T> {
  final T? data;
  final String? error;
  final bool success;

  StorageResult.success(this.data) : error = null, success = true;
  StorageResult.failure(this.error) : data = null, success = false;
}

/// 笔记存储服务
///
/// 负责笔记数据的持久化存储，使用 SQLite 作为存储引擎。
class NoteStorageService {
  static const String _dbName = 'notes.db';
  static const int _dbVersion = 1;
  static const String _tableNotes = 'notes';
  static const String _tableMeta = 'meta';

  Database? _db;
  String? _lastError;
  String? get lastError => _lastError;

  /// 初始化存储服务
  Future<StorageResult<void>> init() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, _dbName);

      _db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
      );

      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '初始化存储失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableNotes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'rich_text',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_notes_updated_at ON $_tableNotes (updated_at DESC)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableMeta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  void _ensureInitialized() {
    if (_db == null) {
      throw StateError('NoteStorageService 未初始化，请先调用 init()');
    }
  }

  /// 保存笔记
  Future<StorageResult<void>> saveNote(Note note) async {
    try {
      _ensureInitialized();
      await _db!.insert(
        _tableNotes,
        note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '保存笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 加载所有笔记
  Future<StorageResult<List<Note>>> loadNotes() async {
    try {
      _ensureInitialized();
      final maps = await _db!.query(_tableNotes);
      final notes = maps.map((m) => Note.fromMap(m)).toList();
      _lastError = null;
      return StorageResult.success(notes);
    } catch (e) {
      _lastError = '加载笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 根据 ID 加载笔记
  Future<StorageResult<Note?>> loadNoteById(String id) async {
    try {
      _ensureInitialized();
      final maps = await _db!.query(
        _tableNotes,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isEmpty) {
        _lastError = null;
        return StorageResult.success(null);
      }
      _lastError = null;
      return StorageResult.success(Note.fromMap(maps.first));
    } catch (e) {
      _lastError = '加载笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 删除笔记
  Future<StorageResult<void>> deleteNote(String id) async {
    try {
      _ensureInitialized();
      await _db!.delete(_tableNotes, where: 'id = ?', whereArgs: [id]);
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '删除笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 搜索笔记
  Future<StorageResult<List<Note>>> searchNotes(String query) async {
    try {
      _ensureInitialized();
      if (query.isEmpty) {
        return loadNotes();
      }
      final lowerQuery = '%${query.toLowerCase()}%';
      final maps = await _db!.query(
        _tableNotes,
        where: 'LOWER(title) LIKE ? OR LOWER(content) LIKE ?',
        whereArgs: [lowerQuery, lowerQuery],
      );
      final notes = maps.map((m) => Note.fromMap(m)).toList();
      _lastError = null;
      return StorageResult.success(notes);
    } catch (e) {
      _lastError = '搜索笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 获取按更新时间排序的笔记列表
  Future<StorageResult<List<Note>>> loadNotesSortedByUpdatedAt() async {
    try {
      _ensureInitialized();
      final maps = await _db!.query(
        _tableNotes,
        orderBy: 'updated_at DESC',
      );
      final notes = maps.map((m) => Note.fromMap(m)).toList();
      _lastError = null;
      return StorageResult.success(notes);
    } catch (e) {
      _lastError = '加载笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  // ==================== 自动保存功能 ====================

  Timer? _autoSaveTimer;
  Note? _pendingNote;

  void scheduleAutoSave(Note note, {Duration delay = const Duration(seconds: 2)}) {
    _pendingNote = note;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(delay, () async {
      if (_pendingNote != null) {
        final result = await saveNote(_pendingNote!);
        if (!result.success) {
          debugPrint('自动保存失败: ${result.error}');
        }
        _pendingNote = null;
      }
    });
  }

  Future<StorageResult<void>> flushAutoSave() async {
    _autoSaveTimer?.cancel();
    if (_pendingNote != null) {
      final result = await saveNote(_pendingNote!);
      _pendingNote = null;
      return result;
    }
    return StorageResult.success(null);
  }

  // ==================== 数据迁移 ====================

  /// 从 Hive JSON 数据迁移到 SQLite
  Future<StorageResult<void>> migrateFromHive(List<Map<String, dynamic>> hiveNotes) async {
    try {
      _ensureInitialized();
      final meta = await _db!.query(
        _tableMeta,
        where: 'key = ?',
        whereArgs: ['hive_migrated'],
      );
      if (meta.isNotEmpty) {
        return StorageResult.success(null);
      }

      if (hiveNotes.isNotEmpty) {
        final batch = _db!.batch();
        for (final json in hiveNotes) {
          final note = Note.fromJson(json);
          batch.insert(
            _tableNotes,
            note.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      await _db!.insert(_tableMeta, {
        'key': 'hive_migrated',
        'value': 'true',
      });

      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '数据迁移失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  // ==================== 资源清理 ====================

  Future<void> close() async {
    _autoSaveTimer?.cancel();
    await _db?.close();
  }
}
