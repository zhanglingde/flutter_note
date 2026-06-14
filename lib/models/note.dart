/// 笔记同步状态
enum SyncStatus {
  /// 本地与远端一致（或本地有、远端有的快照）
  clean,
  /// 本地有未推送的变更
  dirty,
  /// 处于冲突状态，待用户处理
  conflict;

  static SyncStatus fromString(String? value) {
    switch (value) {
      case 'dirty':
        return dirty;
      case 'conflict':
        return conflict;
      case 'clean':
      default:
        return clean;
    }
  }

  String get name {
    switch (this) {
      case clean:
        return 'clean';
      case dirty:
        return 'dirty';
      case conflict:
        return 'conflict';
    }
  }
}

/// 笔记数据模型
class Note {
  String id;
  String title;
  String content;
  String type; // 'rich_text'
  DateTime createdAt;
  DateTime updatedAt;

  // 同步相关字段（v2 数据库新增）
  SyncStatus syncStatus;
  String? remoteEtag;
  String? localHash;
  DateTime? deletedAt;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.clean,
    this.remoteEtag,
    this.localHash,
    this.deletedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      type: json['type'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      syncStatus: SyncStatus.fromString(json['syncStatus'] as String?),
      remoteEtag: json['remoteEtag'] as String?,
      localHash: json['localHash'] as String?,
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus.name,
      'remoteEtag': remoteEtag,
      'localHash': localHash,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as String,
      title: (map['title'] ?? '') as String,
      content: (map['content'] ?? '') as String,
      type: (map['type'] ?? 'rich_text') as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      remoteEtag: map['remote_etag'] as String?,
      localHash: map['local_hash'] as String?,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'sync_status': syncStatus.name,
      'remote_etag': remoteEtag,
      'local_hash': localHash,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    Object? remoteEtag = _sentinel,
    Object? localHash = _sentinel,
    Object? deletedAt = _sentinel,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      remoteEtag: identical(remoteEtag, _sentinel)
          ? this.remoteEtag
          : remoteEtag as String?,
      localHash: identical(localHash, _sentinel)
          ? this.localHash
          : localHash as String?,
      deletedAt: identical(deletedAt, _sentinel)
          ? this.deletedAt
          : deletedAt as DateTime?,
    );
  }

  static const Object _sentinel = Object();
}
