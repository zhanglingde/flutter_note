import 'package:flutter_test/flutter_test.dart';
import 'package:note/utils/cn_en_formatter.dart';

void main() {
  group('CnEnFormatter.formatText', () {
    test('中文后跟英文加空格', () {
      expect(CnEnFormatter.formatText('你好world'), '你好 world');
    });

    test('英文后跟中文加空格', () {
      expect(CnEnFormatter.formatText('hello世界'), 'hello 世界');
    });

    test('中文后跟数字加空格', () {
      expect(CnEnFormatter.formatText('第3章'), '第 3 章');
    });

    test('数字后跟中文加空格', () {
      expect(CnEnFormatter.formatText('2025年'), '2025 年');
    });

    test('已有空格不重复添加', () {
      expect(CnEnFormatter.formatText('你好 world'), '你好 world');
    });

    test('全角标点间不加空格', () {
      expect(CnEnFormatter.formatText('你好，世界'), '你好，世界');
    });

    test('纯中文不变', () {
      expect(CnEnFormatter.formatText('你好世界'), '你好世界');
    });

    test('纯英文不变', () {
      expect(CnEnFormatter.formatText('hello world'), 'hello world');
    });

    test('纯数字不变', () {
      expect(CnEnFormatter.formatText('123 456'), '123 456');
    });

    test('多边界混合', () {
      expect(
        CnEnFormatter.formatText('第3次meeting在2025年'),
        '第 3 次 meeting 在 2025 年',
      );
    });

    test('空字符串不变', () {
      expect(CnEnFormatter.formatText(''), '');
    });

    group('中文文案排版指北规则', () {
      test('数字与单位之间加空格：10Gbps → 10 Gbps', () {
        expect(CnEnFormatter.formatText('10Gbps'), '10 Gbps');
      });

      test('数字与单位之间加空格：20TB → 20 TB', () {
        expect(CnEnFormatter.formatText('20TB'), '20 TB');
      });

      test('数字与单位之间加空格：100MB → 100 MB', () {
        expect(CnEnFormatter.formatText('100MB'), '100 MB');
      });

      test('百分号前不加空格：15 % → 15%', () {
        expect(CnEnFormatter.formatText('15 %'), '15%');
      });

      test('度号前不加空格：90 ° → 90°', () {
        expect(CnEnFormatter.formatText('90 °'), '90°');
      });

      test('数字与单位已有空格不重复添加', () {
        expect(CnEnFormatter.formatText('10 Gbps'), '10 Gbps');
      });

      test('百分号无空格不变', () {
        expect(CnEnFormatter.formatText('15%'), '15%');
      });

      test('CJK 扩展字符范围（康熙部首等）', () {
        expect(CnEnFormatter.formatText('金price'), '金 price');
      });

      test('中文与单位混合场景', () {
        expect(
          CnEnFormatter.formatText('带宽10Gbps，占用率15%'),
          '带宽 10 Gbps，占用率 15%',
        );
      });
    });
  });
}
