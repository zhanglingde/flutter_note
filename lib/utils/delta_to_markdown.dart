import 'dart:convert';

/// 将 Quill Delta JSON 字符串转换为 Markdown 文本
String deltaToMarkdown(String deltaJson) {
  if (deltaJson.isEmpty || deltaJson == '[]') return '';

  final List<dynamic> ops;
  try {
    ops = jsonDecode(deltaJson) as List<dynamic>;
  } catch (_) {
    return '';
  }

  final lines = <_Line>[];
  var currentLine = _Line();

  for (final op in ops) {
    if (op is! Map<String, dynamic>) continue;
    final data = op['insert'];
    final attrs = op['attributes'] as Map<String, dynamic>?;

    if (data is Map<String, dynamic>) {
      // 嵌入对象
      if (data.containsKey('image')) {
        final imageSource = data['image'];
        String url;
        if (imageSource is String) {
          url = imageSource;
        } else if (imageSource is Map) {
          url = imageSource['source']?.toString() ?? '';
        } else {
          url = imageSource.toString();
        }
        currentLine.inlines.add(_Inline('![]($url)', null));
      }
      if (data.containsKey('video')) {
        final videoSource = data['video'];
        String url;
        if (videoSource is String) {
          try {
            final json = jsonDecode(videoSource) as Map<String, dynamic>;
            url = json['source']?.toString() ?? '';
          } catch (_) {
            url = videoSource;
          }
        } else if (videoSource is Map) {
          url = videoSource['source']?.toString() ?? '';
        } else {
          url = videoSource.toString();
        }
        currentLine.inlines.add(_Inline('![video]($url)', null));
      }
      continue;
    }

    if (data is! String) continue;
    final text = data;

    // 处理换行分割行
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\n') {
        // 换行前的文本加到当前行
        if (i > start) {
          currentLine.inlines
              .add(_Inline(text.substring(start, i), attrs));
        }
        // 换行的属性决定当前行的块级格式
        currentLine.lineAttrs = attrs;
        lines.add(currentLine);
        currentLine = _Line();
        start = i + 1;
      }
    }
    // 行尾剩余文本
    if (start < text.length) {
      currentLine.inlines
          .add(_Inline(text.substring(start), attrs));
    }
  }
  // 最后一行（如果没有以 \n 结尾）
  if (currentLine.inlines.isNotEmpty) {
    lines.add(currentLine);
  }

  return lines.map((line) => line.toMarkdown()).join('\n');
}

/// 一行的数据
class _Line {
  final List<_Inline> inlines = [];
  Map<String, dynamic>? lineAttrs;

  String toMarkdown() {
    final text = inlines.map((i) => i.toMarkdown()).join();

    if (lineAttrs == null) return text;

    final header = lineAttrs!['header'];
    if (header == 1) return '# $text';
    if (header == 2) return '## $text';
    if (header == 3) return '### $text';

    if (lineAttrs!['list'] == 'bullet') return '- $text';
    if (lineAttrs!['list'] == 'ordered') return '1. $text';

    if (lineAttrs!['blockquote'] == true) return '> $text';

    if (lineAttrs!['code-block'] == true) return '    $text';

    return text;
  }
}

/// 行内文本段
class _Inline {
  final String text;
  final Map<String, dynamic>? attrs;

  _Inline(this.text, this.attrs);

  String toMarkdown() {
    if (text.isEmpty) return text;

    var result = text;

    if (attrs == null) return result;

    // 行内代码优先（内部不再包裹其他格式）
    if (attrs!['code'] == true) return '`$result`';

    // 链接
    final link = attrs!['link'];
    if (link != null) return '[$result]($link)';

    // 按固定顺序包裹格式标记
    final markers = <String>[];
    if (attrs!['bold'] == true) markers.add('**');
    if (attrs!['italic'] == true) markers.add('*');
    if (attrs!['strike'] == true) markers.add('~~');

    for (final m in markers) {
      result = '$m$result$m';
    }

    return result;
  }
}
