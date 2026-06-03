import 'package:dart_quill_delta/dart_quill_delta.dart';

/// 将 Markdown 文本转换为 Quill Delta 操作列表
Delta markdownToDelta(String markdown) {
  final delta = Delta();
  final lines = markdown.split('\n');
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];

    // 空行
    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    // 标题
    final headingMatch = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length;
      final content = headingMatch.group(2)!;
      final attr = level == 1
          ? {'header': 1}
          : level == 2
              ? {'header': 2}
              : {'header': 3};
      delta.insert(content, attr);
      delta.insert('\n');
      i++;
      continue;
    }

    // 代码块
    if (line.trimLeft().startsWith('```')) {
      final codeLines = <String>[];
      i++;
      while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
        codeLines.add(lines[i]);
        i++;
      }
      i++; // skip closing ```
      if (codeLines.isNotEmpty) {
        delta.insert('${codeLines.join('\n')}\n', {'code-block': true});
      }
      continue;
    }

    // 引用块
    final blockquoteMatch = RegExp(r'^>\s*(.*)$').firstMatch(line);
    if (blockquoteMatch != null) {
      _appendInlineContent(delta, blockquoteMatch.group(1)!);
      delta.insert('\n', {'blockquote': true});
      i++;
      continue;
    }

    // 无序列表
    final ulMatch = RegExp(r'^[-*]\s+(.*)$').firstMatch(line);
    if (ulMatch != null) {
      _appendInlineContent(delta, ulMatch.group(1)!);
      delta.insert('\n', {'list': 'bullet'});
      i++;
      continue;
    }

    // 有序列表
    final olMatch = RegExp(r'^\d+\.\s+(.*)$').firstMatch(line);
    if (olMatch != null) {
      _appendInlineContent(delta, olMatch.group(1)!);
      delta.insert('\n', {'list': 'ordered'});
      i++;
      continue;
    }

    // 图片（独占一行）
    final imgMatch = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)').firstMatch(line);
    if (imgMatch != null && line.trim() == imgMatch.group(0)) {
      delta.insert({'image': imgMatch.group(2)!});
      delta.insert('\n');
      i++;
      continue;
    }

    // 普通段落
    _appendInlineContent(delta, line);
    delta.insert('\n');
    i++;
  }

  // 去除末尾多余换行
  final ops = delta.toList();
  if (ops.isNotEmpty) {
    final last = ops.last;
    if (last.isInsert &&
        last.data == '\n' &&
        (last.attributes == null || last.attributes!.isEmpty)) {
      delta.delete(1);
    }
  }

  return delta;
}

/// 解析行内 Markdown 并直接追加到 delta
void _appendInlineContent(Delta delta, String text) {
  final segments = _parseInlineSegments(text);
  for (final seg in segments) {
    delta.insert(seg.text, seg.attributes);
  }
}

/// 行内文本段
class _Segment {
  final String text;
  final Map<String, dynamic>? attributes;
  _Segment(this.text, this.attributes);
}

/// 解析行内 Markdown，返回有序的文本段列表
List<_Segment> _parseInlineSegments(String text) {
  final matches = <_InlineMatch>[];
  final processed = List.filled(text.length, false);

  // 1. 行内代码（优先匹配，内部不再解析）
  for (final match in RegExp(r'`([^`]+)`').allMatches(text)) {
    if (_isOverlapping(processed, match.start, match.end)) continue;
    _markProcessed(processed, match.start, match.end);
    matches.add(_InlineMatch(
      start: match.start,
      end: match.end,
      text: match.group(1)!,
      attributes: {'code': true},
    ));
  }

  // 2. 链接 [text](url)
  for (final match
      in RegExp(r'\[([^\]]+)\]\(([^)]+)\)').allMatches(text)) {
    if (_isOverlapping(processed, match.start, match.end)) continue;
    _markProcessed(processed, match.start, match.end);
    matches.add(_InlineMatch(
      start: match.start,
      end: match.end,
      text: match.group(1)!,
      attributes: {'link': match.group(2)!},
    ));
  }

  // 3. 粗体 **text** 或 __text__
  for (final match in RegExp(r'\*\*(.+?)\*\*|__(.+?)__').allMatches(text)) {
    if (_isOverlapping(processed, match.start, match.end)) continue;
    _markProcessed(processed, match.start, match.end);
    matches.add(_InlineMatch(
      start: match.start,
      end: match.end,
      text: match.group(1) ?? match.group(2)!,
      attributes: {'bold': true},
    ));
  }

  // 4. 斜体 *text*（排除粗体标记）
  for (final match
      in RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)').allMatches(text)) {
    if (_isOverlapping(processed, match.start, match.end)) continue;
    _markProcessed(processed, match.start, match.end);
    matches.add(_InlineMatch(
      start: match.start,
      end: match.end,
      text: match.group(1)!,
      attributes: {'italic': true},
    ));
  }

  // 5. 删除线 ~~text~~
  for (final match in RegExp(r'~~(.+?)~~').allMatches(text)) {
    if (_isOverlapping(processed, match.start, match.end)) continue;
    _markProcessed(processed, match.start, match.end);
    matches.add(_InlineMatch(
      start: match.start,
      end: match.end,
      text: match.group(1)!,
      attributes: {'strike': true},
    ));
  }

  // 没有 inline 标记
  if (matches.isEmpty) return [_Segment(text, null)];

  // 按位置排序
  matches.sort((a, b) => a.start.compareTo(b.start));

  // 构建结果：交替填充普通文本和带格式文本
  final result = <_Segment>[];
  var pos = 0;

  for (final m in matches) {
    if (m.start > pos) {
      result.add(_Segment(text.substring(pos, m.start), null));
    }
    result.add(_Segment(m.text, m.attributes));
    pos = m.end;
  }

  if (pos < text.length) {
    result.add(_Segment(text.substring(pos), null));
  }

  return result;
}

void _markProcessed(List<bool> processed, int start, int end) {
  for (var i = start; i < end; i++) {
    processed[i] = true;
  }
}

bool _isOverlapping(List<bool> processed, int start, int end) {
  for (var i = start; i < end; i++) {
    if (processed[i]) return true;
  }
  return false;
}

class _InlineMatch {
  final int start;
  final int end;
  final String text;
  final Map<String, dynamic> attributes;

  _InlineMatch({
    required this.start,
    required this.end,
    required this.text,
    required this.attributes,
  });
}
