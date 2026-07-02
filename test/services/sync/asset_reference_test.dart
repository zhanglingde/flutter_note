import 'package:flutter_test/flutter_test.dart';
import 'package:note/services/sync/asset_reference.dart';

void main() {
  group('AssetReference', () {
    test('build uri from hash and ext', () {
      final ref = AssetReference('a3f5e8b9', 'png');
      expect(ref.uri, 'asset://a3f5e8b9.png');
    });

    test('tryParse valid asset uri', () {
      final ref = AssetReference.tryParse('asset://a3f5e8b9.png');
      expect(ref, isNotNull);
      expect(ref!.hash, 'a3f5e8b9');
      expect(ref.ext, 'png');
    });

    test('tryParse returns null for non-asset scheme', () {
      expect(AssetReference.tryParse('https://example.com/x.png'), isNull);
      expect(AssetReference.tryParse('file:///C:/x.png'), isNull);
      expect(AssetReference.tryParse(r'C:\Users\x\y.png'), isNull);
      expect(AssetReference.tryParse('/data/user/0/x.png'), isNull);
    });

    test('tryParse returns null for malformed input', () {
      expect(AssetReference.tryParse(null), isNull);
      expect(AssetReference.tryParse(''), isNull);
      expect(AssetReference.tryParse('asset://'), isNull);
      expect(AssetReference.tryParse('asset://noext'), isNull);
      expect(AssetReference.tryParse('asset://.png'), isNull);
      expect(AssetReference.tryParse('asset://abc.'), isNull);
    });

    test('tryParse handles absolute path on disk (legacy)', () {
      const winPath = r'C:\Users\Admin\AppData\images\n1\123.png';
      expect(AssetReference.tryParse(winPath), isNull);
    });

    test('tryParse handles multi-dot filename', () {
      final ref = AssetReference.tryParse('asset://abc.tar.gz');
      expect(ref!.hash, 'abc.tar');
      expect(ref.ext, 'gz');
    });

    test('equality based on hash+ext', () {
      expect(AssetReference('a', 'png'), AssetReference('a', 'png'));
      expect(AssetReference('a', 'png') == AssetReference('a', 'jpg'), isFalse);
    });
  });

  group('scanHashes', () {
    test('scanHashes extracts all asset hashes from content', () {
      const hash1 = 'aaaa1111bbbb2222cccc3333dddd444455556666';
      const hash2 = 'bbbb1111bbbb2222cccc3333dddd4444555566667777'; // 64 字符
      // hash1 40 字符，hash2 64 字符，都在 40-128 范围内
      final content =
          '{"insert":{"image":"asset://$hash1.png"}}'
          '{"insert":{"video":"asset://$hash2.mp4"}}'
          '{"insert":"\\n"}';
      final hashes = AssetReference.scanHashes(content);
      expect(hashes.length, 2);
      expect(hashes, contains(hash1));
      expect(hashes, contains(hash2));
    });

    test('scanHashes returns empty set for content without asset refs', () {
      expect(AssetReference.scanHashes('hello world'), isEmpty);
      expect(AssetReference.scanHashes(''), isEmpty);
    });

    test('scanHashes ignores non-hex hash content', () {
      // 40 字符但含非 hex 字符 → 不匹配
      const content = 'asset://zzzz1111zzzz2222zzzz3333zzzz4444zzzz.png';
      expect(AssetReference.scanHashes(content), isEmpty);
    });
  });
}
