import 'package:flutter_test/flutter_test.dart';
import 'package:note/models/note.dart';

void main() {
  group('Note Model Tests', () {
    test('Note should be created with correct properties', () {
      final now = DateTime.now();
      final note = Note(
        id: '1',
        title: 'Test Note',
        content: 'Test content',
        type: 'rich_text',
        createdAt: now,
        updatedAt: now,
      );

      expect(note.id, '1');
      expect(note.title, 'Test Note');
      expect(note.content, 'Test content');
      expect(note.type, 'rich_text');
    });

    test('Note should convert to and from JSON correctly', () {
      final now = DateTime.now();
      final note = Note(
        id: '1',
        title: 'Test Note',
        content: 'Test content',
        type: 'rich_text',
        createdAt: now,
        updatedAt: now,
      );

      final json = note.toJson();
      final noteFromJson = Note.fromJson(json);

      expect(noteFromJson.id, note.id);
      expect(noteFromJson.title, note.title);
      expect(noteFromJson.content, note.content);
      expect(noteFromJson.type, note.type);
    });

    test('Note copyWith should work correctly', () {
      final now = DateTime.now();
      final note = Note(
        id: '1',
        title: 'Original',
        content: 'Original content',
        type: 'rich_text',
        createdAt: now,
        updatedAt: now,
      );

      final updatedNote = note.copyWith(title: 'Updated');

      expect(updatedNote.id, note.id);
      expect(updatedNote.title, 'Updated');
      expect(updatedNote.content, note.content);
    });

    test('Note should support sync fields with defaults', () {
      final now = DateTime.now();
      final note = Note(
        id: '1',
        title: 'T',
        content: 'C',
        type: 'rich_text',
        createdAt: now,
        updatedAt: now,
      );
      expect(note.syncStatus, SyncStatus.clean);
      expect(note.remoteEtag, isNull);
      expect(note.localHash, isNull);
      expect(note.deletedAt, isNull);
    });

    test('Note toMap/fromMap round-trip preserves sync fields', () {
      // toMap 使用 millisecondsSinceEpoch 存储时间，会丢弃微秒精度，
      // 因此构造时先把时间截断到毫秒，以避免微秒非零导致的 flaky 比较。
      final now = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
      );
      final deleted = now.subtract(const Duration(hours: 1));
      final note = Note(
        id: 'abc',
        title: 'T',
        content: 'C',
        type: 'rich_text',
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.dirty,
        remoteEtag: '"etag-1"',
        localHash: 'sha256-abc',
        deletedAt: deleted,
      );
      final restored = Note.fromMap(note.toMap());
      expect(restored.syncStatus, SyncStatus.dirty);
      expect(restored.remoteEtag, '"etag-1"');
      expect(restored.localHash, 'sha256-abc');
      expect(restored.deletedAt, deleted);
    });

    test('Note toMap without sync fields works (backward compat)', () {
      // 模拟旧数据库迁移过来的行：缺少新字段
      final map = {
        'id': '1',
        'title': 'T',
        'content': 'C',
        'type': 'rich_text',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      final note = Note.fromMap(map);
      expect(note.syncStatus, SyncStatus.clean);
      expect(note.deletedAt, isNull);
    });
  });
}
