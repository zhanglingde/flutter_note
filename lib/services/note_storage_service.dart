import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
export 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;
import 'package:path/path.dart' as p;
import '../models/note.dart';

/// sync_assets 表的记录
class SyncAssetRecord {
  final String hash;
  final String ext;
  final String localPath;
  final String? remoteEtag;
  final SyncStatus syncStatus;
  final int refCount;

  SyncAssetRecord({
    required this.hash,
    required this.ext,
    required this.localPath,
    required this.remoteEtag,
    required this.syncStatus,
    required this.refCount,
  });

  factory SyncAssetRecord.fromMap(Map<String, dynamic> map) {
    return SyncAssetRecord(
      hash: map['hash'] as String,
      ext: map['ext'] as String,
      localPath: map['local_path'] as String,
      remoteEtag: map['remote_etag'] as String?,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      refCount: (map['ref_count'] as num?)?.toInt() ?? 0,
    );
  }
}

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
  static const int _dbVersion = 2;
  static const String _tableNotes = 'notes';
  static const String _tableMeta = 'meta';

  Database? _db;
  String? _lastError;
  String? get lastError => _lastError;

  /// 仅用于测试：覆盖 DB 文件所在目录，避免污染真实应用数据。
  @visibleForTesting
  String? dbPathOverride;

  /// 初始化存储服务
  Future<StorageResult<void>> init() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // 测试模式下 dbPathOverride 已提供，跳过 path_provider
      // 正常模式下使用系统应用数据目录，避免 flutter clean 误删
      final String dbPath;
      if (dbPathOverride != null) {
        dbPath = dbPathOverride!;
      } else {
        final appDir = await getApplicationSupportDirectory();
        dbPath = appDir.path;
      }
      final path = p.join(dbPath, _dbName);

      _db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
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
        updated_at INTEGER NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'clean',
        remote_etag TEXT,
        local_hash TEXT,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_notes_updated_at ON $_tableNotes (updated_at DESC)');
    await db.execute('''
      CREATE TABLE $_tableMeta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_assets (
        hash TEXT PRIMARY KEY,
        ext TEXT NOT NULL,
        local_path TEXT NOT NULL,
        remote_etag TEXT,
        sync_status TEXT NOT NULL DEFAULT 'clean',
        ref_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE $_tableNotes ADD COLUMN sync_status TEXT NOT NULL DEFAULT \'clean\'');
      await db.execute('ALTER TABLE $_tableNotes ADD COLUMN remote_etag TEXT');
      await db.execute('ALTER TABLE $_tableNotes ADD COLUMN local_hash TEXT');
      await db.execute('ALTER TABLE $_tableNotes ADD COLUMN deleted_at INTEGER');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_assets (
          hash TEXT PRIMARY KEY,
          ext TEXT NOT NULL,
          local_path TEXT NOT NULL,
          remote_etag TEXT,
          sync_status TEXT NOT NULL DEFAULT 'clean',
          ref_count INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_state (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  void _ensureInitialized() {
    if (_db == null) {
      throw StateError('NoteStorageService 未初始化，请先调用 init()');
    }
  }

  /// 保存笔记
  ///
  /// 任务 14 同步集成行为：如果笔记当前 syncStatus 为 clean 且未被软删除，
  /// 自动升级为 dirty（表示本地有未推送变更）。这样上层 UI 在编辑后只需调用
  /// saveNote 即可，无需显式管理 syncStatus。
  ///
  /// 例外：已软删除的墓碑（deletedAt != null）保持原 syncStatus，避免破坏
  /// 墓碑状态。conflict 状态也保持，等待用户决策。
  ///
  /// 同步引擎（[SyncService]）内部需要保留 clean 状态时，应使用
  /// [saveNoteFromSync] 而非本方法，以绕过自动 dirty 升级。
  Future<StorageResult<void>> saveNote(Note note) async {
    try {
      _ensureInitialized();
      final toSave = note.syncStatus == SyncStatus.clean &&
              note.deletedAt == null
          ? note.copyWith(syncStatus: SyncStatus.dirty)
          : note;
      await _db!.insert(
        _tableNotes,
        toSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '保存笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 同步引擎专用：按笔记原 syncStatus 直接持久化，不做任何自动升级。
  ///
  /// [SyncService] 在 Pull / Push / 冲突解决路径下，明确知道笔记应该处于
  /// 哪种 sync_status（通常是 clean），调用本方法以保留该状态。普通 UI
  /// 编辑流程不应调用本方法，应使用 [saveNote]。
  Future<StorageResult<void>> saveNoteFromSync(Note note) async {
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

  /// 加载所有未删除的笔记（不含墓碑）
  ///
  /// 墓碑（deleted_at 非空的笔记）应通过 [loadAllNotesIncludingDeleted] 获取，
  /// 给同步流程使用。
  Future<StorageResult<List<Note>>> loadNotes() async {
    try {
      _ensureInitialized();
      final maps = await _db!.query(
        _tableNotes,
        where: 'deleted_at IS NULL',
      );
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

  /// 获取按更新时间排序的笔记列表（不含墓碑）
  ///
  /// 给 HomeScreen 笔记列表使用，墓碑不应展示给用户。
  Future<StorageResult<List<Note>>> loadNotesSortedByUpdatedAt() async {
    try {
      _ensureInitialized();
      final maps = await _db!.query(
        _tableNotes,
        where: 'deleted_at IS NULL',
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

  // ==================== 同步查询 ====================

  /// 加载所有笔记（含已软删除的墓碑）
  Future<StorageResult<List<Note>>> loadAllNotesIncludingDeleted() async {
    try {
      _ensureInitialized();
      final maps = await _db!.query(_tableNotes);
      return StorageResult.success(maps.map((m) => Note.fromMap(m)).toList());
    } catch (e) {
      _lastError = '加载笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 加载指定 sync_status 的笔记
  Future<StorageResult<List<Note>>> loadNotesBySyncStatus(
      SyncStatus syncStatus) async {
    try {
      _ensureInitialized();
      final maps = await _db!.query(_tableNotes,
          where: 'sync_status = ?', whereArgs: [syncStatus.name]);
      return StorageResult.success(maps.map((m) => Note.fromMap(m)).toList());
    } catch (e) {
      _lastError = '加载笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  // ==================== sync_assets 表 ====================

  /// Upsert 资源记录。
  ///
  /// 注意：使用 `ConflictAlgorithm.replace`，**`refCount` 是覆盖语义而非累加**。
  /// 如果资源已存在且需要增加引用计数，调用方需先 [listSyncAssets] 读取
  /// 当前 refCount，加 1 后再用新值调用本方法。
  Future<StorageResult<void>> upsertSyncAsset({
    required String hash,
    required String ext,
    required String localPath,
    String? remoteEtag,
    required SyncStatus syncStatus,
    int refCount = 0,
  }) async {
    try {
      _ensureInitialized();
      await _db!.insert(
        'sync_assets',
        {
          'hash': hash,
          'ext': ext,
          'local_path': localPath,
          'remote_etag': remoteEtag,
          'sync_status': syncStatus.name,
          'ref_count': refCount,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '保存同步资源失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  Future<StorageResult<List<SyncAssetRecord>>> listSyncAssets() async {
    try {
      _ensureInitialized();
      final maps = await _db!.query('sync_assets');
      final records =
          maps.map((m) => SyncAssetRecord.fromMap(m)).toList();
      _lastError = null;
      return StorageResult.success(records);
    } catch (e) {
      _lastError = '加载同步资源失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  Future<StorageResult<void>> deleteSyncAsset(String hash) async {
    try {
      _ensureInitialized();
      await _db!.delete('sync_assets', where: 'hash = ?', whereArgs: [hash]);
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '删除同步资源失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  // ==================== sync_state 表 ====================

  Future<StorageResult<void>> setSyncState(String key, String value) async {
    try {
      _ensureInitialized();
      await _db!.insert(
        'sync_state',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '保存同步状态失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 读取同步状态键值。
  ///
  /// key 不存在时返回 `StorageResult.success(null)`（成功 + null），
  /// 这是预期语义而非错误。
  Future<StorageResult<String?>> getSyncState(String key) async {
    try {
      _ensureInitialized();
      final maps = await _db!.query('sync_state',
          where: 'key = ?', whereArgs: [key], limit: 1);
      _lastError = null;
      if (maps.isEmpty) return StorageResult.success(null);
      return StorageResult.success(maps.first['value'] as String);
    } catch (e) {
      _lastError = '读取同步状态失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  // ==================== 资源清理 ====================

  Future<void> close() async {
    _autoSaveTimer?.cancel();
    await _db?.close();
  }
}
