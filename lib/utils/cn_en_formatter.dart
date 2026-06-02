import 'package:flutter_quill/flutter_quill.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';

/// 中英文混排空格格式化（遵循中文文案排版指北）
class CnEnFormatter {
  // 覆盖 CJK Radicals、Kangxi Radicals、CJK Unified Ideographs、
  // CJK Compatibility Ideographs、CJK Compatibility Forms
  static final _cjk = r'[⺀-鿿豈-﫿︰-﹏]';

  static final _cnFollowedByEn = RegExp('($_cjk)([a-zA-Z0-9])');
  static final _enFollowedByCn = RegExp('([a-zA-Z0-9])($_cjk)');

  // 数字后跟字母（单位）：10Gbps → 10 Gbps
  static final _digitFollowedByUnit = RegExp(r'(\d)([A-Za-z]+)');
  // 字母（单位）后跟数字：Gbps10 → Gbps 10
  static final _unitFollowedByDigit = RegExp(r'([A-Za-z]+)(\d)');

  // 百分号/度号：去掉数字与 %/° 之间的空格
  static final _spaceBeforePercent = RegExp(r'(\d)\s+(%)');
  static final _spaceBeforeDegree = RegExp(r'(\d)\s+(°)');

  /// 格式化纯文本
  static String formatText(String text) {
    var result = text;
    // 先处理中文与英文/数字边界
    result = result.replaceAllMapped(
      _cnFollowedByEn,
      (m) => '${m[1]} ${m[2]}',
    );
    result = result.replaceAllMapped(
      _enFollowedByCn,
      (m) => '${m[1]} ${m[2]}',
    );
    // 数字与单位边界
    result = result.replaceAllMapped(
      _digitFollowedByUnit,
      (m) => '${m[1]} ${m[2]}',
    );
    result = result.replaceAllMapped(
      _unitFollowedByDigit,
      (m) => '${m[1]} ${m[2]}',
    );
    // 百分号/度号例外：移除多余空格
    result = result.replaceAllMapped(
      _spaceBeforePercent,
      (m) => '${m[1]}${m[2]}',
    );
    result = result.replaceAllMapped(
      _spaceBeforeDegree,
      (m) => '${m[1]}${m[2]}',
    );
    return result;
  }

  /// 格式化 Quill Document：遍历节点，跳过行内代码和代码块，标题前后添加空行
  static void formatDocument(QuillController controller) {
    final document = controller.document;
    // 统一操作：(offset, deleteLen, insertText)
    final ops = <({int offset, int deleteLen, String insertText})>[];

    // 1. 文本格式化
    void visitLeaf(Leaf leaf, bool inCodeBlock) {
      if (inCodeBlock) return;
      if (leaf.style.attributes.containsKey(Attribute.inlineCode.key)) return;

      final original = leaf.value as String;
      final formatted = formatText(original);
      if (formatted != original) {
        ops.add((
          offset: leaf.documentOffset,
          deleteLen: original.length,
          insertText: formatted,
        ));
      }
    }

    // 收集所有行，用于标题检测
    final lines = <Line>[];

    for (final node in document.root.children) {
      if (node is Block) {
        final isCodeBlock =
            node.style.attributes.containsKey(Attribute.codeBlock.key);
        for (final line in node.children) {
          if (line is Line) {
            lines.add(line);
            for (final child in line.children) {
              if (child is Leaf) visitLeaf(child, isCodeBlock);
            }
          }
        }
      } else if (node is Line) {
        lines.add(node);
        for (final child in node.children) {
          if (child is Leaf) visitLeaf(child, false);
        }
      }
    }

    // 2. 标题前后添加空行
    final insertOffsets = <int>{};
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.style.attributes.containsKey(Attribute.header.key)) continue;

      // 标题前：前一行为非空行时插入空行
      if (i > 0 && lines[i - 1].children.isNotEmpty) {
        final offset = line.documentOffset;
        if (insertOffsets.add(offset)) {
          ops.add((offset: offset, deleteLen: 0, insertText: '\n'));
        }
      }

      // 标题后：后一行为非空行时插入空行
      if (i < lines.length - 1 && lines[i + 1].children.isNotEmpty) {
        final offset = line.documentOffset + line.length;
        if (insertOffsets.add(offset)) {
          ops.add((offset: offset, deleteLen: 0, insertText: '\n'));
        }
      }
    }

    if (ops.isEmpty) return;

    // 按偏移量排序，同一偏移量插入操作（deleteLen=0）在替换操作之前
    ops.sort((a, b) {
      final cmp = a.offset.compareTo(b.offset);
      if (cmp != 0) return cmp;
      return a.deleteLen.compareTo(b.deleteLen);
    });

    // 构建 Delta：retain gap → (delete +) insert
    final delta = Delta();
    int currentPos = 0;

    for (final op in ops) {
      if (op.offset > currentPos) {
        delta.retain(op.offset - currentPos);
      }
      if (op.deleteLen > 0) {
        delta.delete(op.deleteLen);
      }
      delta.insert(op.insertText);
      currentPos = op.offset + op.deleteLen;
    }

    controller.compose(delta, controller.selection, ChangeSource.local);
  }
}
