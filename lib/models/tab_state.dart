import 'package:flutter/material.dart';
import 'note.dart';

/// 单个标签页的状态
class TabState {
  final Note note;
  final GlobalKey key;
  DateTime lastAccessedAt;

  TabState({
    required this.note,
    required this.key,
    DateTime? lastAccessedAt,
  }) : lastAccessedAt = lastAccessedAt ?? DateTime.now();

  String get id => note.id;

  TabState copyWith({Note? note, DateTime? lastAccessedAt}) {
    return TabState(
      note: note ?? this.note,
      key: key,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }
}
