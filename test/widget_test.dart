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
  });
}
