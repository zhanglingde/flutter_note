import 'package:path/path.dart' as p;

/// LWW 解析结果
enum ConflictResolution {
  /// 保留本地版本（本地 updatedAt 较新或相等）
  keepLocal,
  /// 保留远程版本（远程 updatedAt 较新）
  keepRemote,
}

/// 冲突解析工具
///
/// 纯函数实现，无副作用，便于测试。
/// 实际的"上传副本"、"覆盖"动作由 [SyncService] 调用 backend 执行。
class ConflictResolver {
  static const String _conflictMarker = '__conflict-';

  /// 根据本地/远程 updatedAt 决定保留方向
  ///
  /// 时间戳相等时默认保留本地（用户最近一次操作意图）。
  static ConflictResolution resolve({
    required DateTime localUpdatedAt,
    required DateTime remoteUpdatedAt,
  }) {
    if (!remoteUpdatedAt.isAfter(localUpdatedAt)) {
      return ConflictResolution.keepLocal;
    }
    return ConflictResolution.keepRemote;
  }

  /// 生成冲突副本路径：在原文件名的扩展名前插入 `__conflict-` 加 ISO 时间戳
  ///
  /// 时间戳格式：`YYYY-MM-DDTHH-MM-SSZ`（ISO8601 的"安全文件名"变体，
  /// 把 `:` `.` 替换为 `-`，截到秒精度，避免 FAT/WebDAV 文件名禁用字符）。
  static String conflictFilename({
    required String notePath,
    required DateTime timestamp,
  }) {
    final dir = p.dirname(notePath);
    final basename = p.basename(notePath);
    final stamp = _formatStamp(timestamp);
    final dotIndex = basename.lastIndexOf('.');
    if (dotIndex <= 0) {
      return '$dir/$basename$_conflictMarker$stamp';
    }
    final name = basename.substring(0, dotIndex);
    final ext = basename.substring(dotIndex);
    return '$dir/$name$_conflictMarker$stamp$ext';
  }

  /// 将时间戳格式化为 `YYYY-MM-DDTHH-MM-SSZ`
  static String _formatStamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final y = utc.year.toString().padLeft(4, '0');
    return '$y-${two(utc.month)}-${two(utc.day)}T'
        '${two(utc.hour)}-${two(utc.minute)}-${two(utc.second)}Z';
  }

  /// 判断路径是否为冲突副本
  static bool isConflictFile(String path) {
    return p.basename(path).contains(_conflictMarker);
  }

  /// 从冲突副本路径提取原笔记 ID（不含扩展名）
  ///
  /// 输入：`/notes/abc-123__conflict-2026-06-14T15-30-00Z.json`
  /// 输出：`abc-123`
  ///
  /// 若路径不含冲突标记则返回 null。
  static String? originalNoteId(String path) {
    final basename = p.basename(path);
    final idx = basename.indexOf(_conflictMarker);
    if (idx < 0) return null;
    final before = basename.substring(0, idx);
    final dotIndex = before.lastIndexOf('.');
    // dotIndex <= 0 表示无扩展名（含前置点隐藏文件名场景）
    // 与 conflictFilename 的 dotIndex <= 0 分支保持一致
    return dotIndex > 0 ? before.substring(0, dotIndex) : before;
  }
}
