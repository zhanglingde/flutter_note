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
        type: 'markdown',
        createdAt: now,
        updatedAt: now,
      );

      expect(note.id, '1');
      expect(note.title, 'Test Note');
      expect(note.content, 'Test content');
      expect(note.type, 'markdown');
      expect(note.noteType, NoteType.markdown);
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
        type: 'markdown',
        createdAt: now,
        updatedAt: now,
      );

      final updatedNote = note.copyWith(title: 'Updated');

      expect(updatedNote.id, note.id);
      expect(updatedNote.title, 'Updated');
      expect(updatedNote.content, note.content);
    });

    test('Note type enum should work correctly', () {
      final richTextNote = Note(
        id: '1',
        title: 'Rich Text',
        content: '[]',
        type: 'rich_text',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final markdownNote = Note(
        id: '2',
        title: 'Markdown',
        content: '# Hello',
        type: 'markdown',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(richTextNote.noteType, NoteType.richText);
      expect(markdownNote.noteType, NoteType.markdown);
    });
  });

  // Note: 存储服务测试需要在实际设备或模拟器上运行
  // 因为 Hive.initFlutter() 需要平台通道支持
}
