import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 单个远程笔记文件的清单条目
class ManifestEntry {
  final String etag;
  final int size;
  final String hash;
  final DateTime updatedAt;

  const ManifestEntry({
    required this.etag,
    required this.size,
    required this.hash,
    required this.updatedAt,
  });

  /// 是否需要下载（基于 etag）
  bool needsDownload({required String? localEtag}) {
    if (localEtag == null) return true;
    return localEtag != etag;
  }

  Map<String, dynamic> toJson() => {
        'etag': etag,
        'size': size,
        'hash': hash,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ManifestEntry.fromJson(Map<String, dynamic> json) {
    return ManifestEntry(
      etag: (json['etag'] ?? '') as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      hash: (json['hash'] ?? '') as String,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 单个远程资源的清单条目
class ManifestAssetEntry {
  final String etag;
  final int size;
  final int refCount;

  const ManifestAssetEntry({
    required this.etag,
    required this.size,
    required this.refCount,
  });

  Map<String, dynamic> toJson() => {
        'etag': etag,
        'size': size,
        'refCount': refCount,
      };

  factory ManifestAssetEntry.fromJson(Map<String, dynamic> json) {
    return ManifestAssetEntry(
      etag: (json['etag'] ?? '') as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      refCount: (json['refCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 远端 manifest.json 的完整结构
class ManifestData {
  final int version;
  final DateTime generatedAt;
  final Map<String, ManifestEntry> notes;
  final Map<String, ManifestAssetEntry> assets;

  const ManifestData({
    required this.version,
    required this.generatedAt,
    required this.notes,
    required this.assets,
  });

  factory ManifestData.empty() => ManifestData(
        version: 1,
        generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        notes: const {},
        assets: const {},
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'generatedAt': generatedAt.toIso8601String(),
        'notes': notes.map((k, v) => MapEntry(k, v.toJson())),
        'assets': assets.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory ManifestData.fromJson(Map<String, dynamic> json) {
    final notesRaw = (json['notes'] as Map<String, dynamic>?) ?? const {};
    final assetsRaw = (json['assets'] as Map<String, dynamic>?) ?? const {};
    return ManifestData(
      version: (json['version'] as num?)?.toInt() ?? 1,
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
      notes: notesRaw.map((k, v) =>
          MapEntry(k, ManifestEntry.fromJson(v as Map<String, dynamic>))),
      assets: assetsRaw.map((k, v) => MapEntry(
          k, ManifestAssetEntry.fromJson(v as Map<String, dynamic>))),
    );
  }

  String encode() => jsonEncode(toJson());

  static ManifestData decode(String? body) {
    if (body == null || body.isEmpty) return ManifestData.empty();
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return ManifestData.fromJson(json);
    } catch (e) {
      debugPrint('ManifestData.decode failed: $e');
      return ManifestData.empty();
    }
  }
}
