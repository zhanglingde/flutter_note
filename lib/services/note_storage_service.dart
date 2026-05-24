import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/note.dart';

/// 存储操作结果
///
/// 封装存储操作的结果，包含成功/失败状态、数据和错误信息。
/// 用于统一处理存储操作可能出现的异常情况。
class StorageResult<T> {
  /// 操作成功时返回的数据
  final T? data;

  /// 操作失败时的错误信息
  final String? error;

  /// 操作是否成功
  final bool success;

  /// 创建成功结果
  StorageResult.success(this.data) : error = null, success = true;

  /// 创建失败结果
  StorageResult.failure(this.error) : data = null, success = false;
}

/// 笔记存储服务
///
/// 负责笔记数据的持久化存储，使用 Hive 作为存储引擎。
///
/// 主要功能：
/// - 笔记的增删改查
/// - 笔记搜索
/// - 自动保存（延迟 2 秒）
///
/// 使用示例：
/// ```dart
/// final storageService = NoteStorageService();
/// await storageService.init();
///
/// // 保存笔记
/// await storageService.saveNote(note);
///
/// // 加载所有笔记
/// final result = storageService.loadNotes();
/// ```
class NoteStorageService {
  /// Hive 存储盒名称
  static const String _boxName = 'notes';

  /// Hive 存储盒实例
  Box<Note>? _box;

  /// 最后一次操作的错误信息
  String? _lastError;

  /// 获取最后的错误信息
  String? get lastError => _lastError;

  /// 初始化存储服务
  ///
  /// 必须在使用其他方法前调用。
  /// 会注册 Hive 适配器并打开存储盒。
  Future<StorageResult<void>> init() async {
    try {
      // 注册 Note 模型的 Hive 适配器（确保只注册一次）
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(NoteAdapter());
      }
      _box = await Hive.openBox<Note>(_boxName);
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '初始化存储失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 确保存储服务已初始化
  void _ensureInitialized() {
    if (_box == null) {
      throw StateError('NoteStorageService 未初始化，请先调用 init()');
    }
  }

  /// 保存笔记
  ///
  /// 如果笔记 ID 已存在，将覆盖原有笔记。
  Future<StorageResult<void>> saveNote(Note note) async {
    try {
      _ensureInitialized();
      await _box!.put(note.id, note);
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '保存笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 加载所有笔记
  StorageResult<List<Note>> loadNotes() {
    try {
      _ensureInitialized();
      _lastError = null;
      return StorageResult.success(_box!.values.toList());
    } catch (e) {
      _lastError = '加载笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 根据 ID 加载笔记
  StorageResult<Note?> loadNoteById(String id) {
    try {
      _ensureInitialized();
      _lastError = null;
      return StorageResult.success(_box!.get(id));
    } catch (e) {
      _lastError = '加载笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 删除笔记
  Future<StorageResult<void>> deleteNote(String id) async {
    try {
      _ensureInitialized();
      await _box!.delete(id);
      _lastError = null;
      return StorageResult.success(null);
    } catch (e) {
      _lastError = '删除笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 搜索笔记
  ///
  /// 在标题和内容中搜索匹配的文本（不区分大小写）。
  /// 如果查询为空，返回所有笔记。
  StorageResult<List<Note>> searchNotes(String query) {
    try {
      _ensureInitialized();
      if (query.isEmpty) {
        return loadNotes();
      }
      final lowerQuery = query.toLowerCase();
      final results = _box!.values.where((note) {
        return note.title.toLowerCase().contains(lowerQuery) ||
            note.content.toLowerCase().contains(lowerQuery);
      }).toList();
      _lastError = null;
      return StorageResult.success(results);
    } catch (e) {
      _lastError = '搜索笔记失败: $e';
      return StorageResult.failure(_lastError);
    }
  }

  /// 获取按更新时间排序的笔记列表
  ///
  /// 按更新时间降序排列（最新的在前）。
  StorageResult<List<Note>> loadNotesSortedByUpdatedAt() {
    final result = loadNotes();
    if (result.success && result.data != null) {
      result.data!.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return result;
  }

  // ==================== 自动保存功能 ====================

  /// 自动保存定时器
  Timer? _autoSaveTimer;

  /// 待保存的笔记
  Note? _pendingNote;

  /// 延迟自动保存
  ///
  /// 会在指定的延迟时间后自动保存笔记。
  /// 如果在延迟期间再次调用，会重置计时器（防抖）。
  /// 默认延迟 2 秒。
  void scheduleAutoSave(
    Note note, {
    Duration delay = const Duration(seconds: 2),
  }) {
    _pendingNote = note;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(delay, () async {
      if (_pendingNote != null) {
        final result = await saveNote(_pendingNote!);
        if (!result.success) {
          // 自动保存失败时打印日志（可替换为全局错误处理）
          debugPrint('自动保存失败: ${result.error}');
        }
        _pendingNote = null;
      }
    });
  }

  /// 立即保存待保存的笔记
  ///
  /// 用于在页面退出时强制保存未完成的自动保存。
  Future<StorageResult<void>> flushAutoSave() async {
    _autoSaveTimer?.cancel();
    if (_pendingNote != null) {
      final result = await saveNote(_pendingNote!);
      _pendingNote = null;
      return result;
    }
    return StorageResult.success(null);
  }

  /// 关闭存储服务
  ///
  /// 释放资源，关闭 Hive 存储盒。
  Future<void> close() async {
    _autoSaveTimer?.cancel();
    await _box?.close();
  }
}
