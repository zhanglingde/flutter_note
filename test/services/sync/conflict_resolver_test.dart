import 'package:flutter_test/flutter_test.dart';
import 'package:note/services/sync/conflict_resolver.dart';

void main() {
  group('conflict filename', () {
    test('appends __conflict-<timestamp> before extension', () {
      final name = ConflictResolver.conflictFilename(
        notePath: '/notes/abc-123.json',
        timestamp: DateTime.utc(2026, 6, 14, 15, 30, 0),
      );
      expect(name, '/notes/abc-123__conflict-2026-06-14T15-30-00Z.json');
    });

    test('handles paths without extension', () {
      final name = ConflictResolver.conflictFilename(
        notePath: '/notes/abc',
        timestamp: DateTime.utc(2026, 6, 14, 15, 30, 0),
      );
      expect(name, '/notes/abc__conflict-2026-06-14T15-30-00Z');
    });
  });

  group('detect conflict', () {
    test('isConflictFile returns true for files with __conflict- segment', () {
      expect(
        ConflictResolver.isConflictFile(
            '/notes/abc__conflict-2026-06-14T15-30-00Z.json'),
        isTrue,
      );
      expect(
        ConflictResolver.isConflictFile('/notes/abc.json'),
        isFalse,
      );
    });
  });

  group('LWW resolution', () {
    final t1 = DateTime.utc(2026, 6, 14, 10);
    final t2 = DateTime.utc(2026, 6, 14, 12);

    test('local newer -> keepLocal', () {
      final r = ConflictResolver.resolve(localUpdatedAt: t2, remoteUpdatedAt: t1);
      expect(r, ConflictResolution.keepLocal);
    });

    test('remote newer -> keepRemote', () {
      final r = ConflictResolver.resolve(localUpdatedAt: t1, remoteUpdatedAt: t2);
      expect(r, ConflictResolution.keepRemote);
    });

    test('equal timestamps -> keepLocal (default tiebreaker)', () {
      final r = ConflictResolver.resolve(localUpdatedAt: t1, remoteUpdatedAt: t1);
      expect(r, ConflictResolution.keepLocal);
    });
  });

  group('original note id from conflict filename', () {
    test('extracts id before __conflict-', () {
      const path = '/notes/abc-123__conflict-2026-06-14T15-30-00Z.json';
      expect(ConflictResolver.originalNoteId(path), 'abc-123');
    });

    test('originalNoteId returns null for non-conflict file', () {
      expect(ConflictResolver.originalNoteId('/notes/abc.json'), isNull);
    });
  });

  test('conflictFilename with dot in name preserves name correctly', () {
    // 多重扩展名：abc.tar.gz → abc.tar__conflict-...gz
    final name = ConflictResolver.conflictFilename(
      notePath: '/notes/abc.tar.gz',
      timestamp: DateTime.utc(2026, 6, 14, 15, 30, 0),
    );
    expect(name, '/notes/abc.tar__conflict-2026-06-14T15-30-00Z.gz');
  });

  test('isConflictFile is true for file with __conflict- in middle of name', () {
    // 任何位置含 __conflict- 都视为冲突文件
    expect(
      ConflictResolver.isConflictFile('/notes/some__conflict-test.json'),
      isTrue,
    );
  });
}
