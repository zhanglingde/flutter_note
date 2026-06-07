import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/dom.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';

export 'clipper/clip_result.dart';

/// HTML → Quill Delta 共享工具方法
class WebClipperService {
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 获取网站 favicon（PNG/JPEG 格式），返回字节数据或 null
  static Future<Uint8List?> fetchFavicon(String url) async {
    try {
      final uri = Uri.parse(url);
      final faviconUrl = Uri.https(uri.host, '/favicon.ico');
      final response = await http
          .get(faviconUrl, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 || response.bodyBytes.length < 100) {
        return null;
      }
      final bytes = response.bodyBytes;
      final isPng = bytes.length >= 4 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
      final isJpeg = bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
      if (!isPng && !isJpeg) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 移除 HTML 噪声元素
  static void removeNoise(Element root) {
    const noiseSelectors = [
      'script', 'style', 'noscript', 'iframe',
      'nav', 'header', 'footer',
      '.ad', '.ads', '.advertisement',
      '.comment', '.comments',
      '.sidebar', '.widget',
      '.share', '.social-share',
      '.related', '.recommend',
      '.toolbar', '.action-bar',
      'svg',
    ];
    for (final selector in noiseSelectors) {
      root.querySelectorAll(selector).forEach((el) => el.remove());
    }
  }

  /// HTML Element → Quill Delta 转换
  static Delta convertHtmlToDelta(Element element) {
    final delta = Delta();
    for (final node in element.nodes) {
      _processNode(node, delta);
    }
    cleanDelta(delta);
    return delta;
  }

  static void _processNode(Node node, Delta delta) {
    if (node is Text) {
      final text = node.text;
      if (text.trim().isNotEmpty) {
        delta.insert(text);
      }
      return;
    }
    if (node is! Element) return;

    final tag = node.localName?.toLowerCase() ?? '';

    switch (tag) {
      case 'h1':
        _processInlineChildren(node, delta);
        delta.insert('\n', {'header': 1});
      case 'h2':
        _processInlineChildren(node, delta);
        delta.insert('\n', {'header': 2});
      case 'h3':
      case 'h4':
        _processInlineChildren(node, delta);
        delta.insert('\n', {'header': 3});
      case 'p':
        _processInlineChildren(node, delta);
        delta.insert('\n');
      case 'blockquote':
        for (final child in node.children) {
          _processInlineChildren(child, delta);
          delta.insert('\n', {'blockquote': true});
        }
      case 'pre':
        final code = node.querySelector('code');
        final text = code?.text ?? node.text;
        if (text.isNotEmpty) {
          delta.insert('$text\n', {'code-block': true});
        }
      case 'ul':
        for (final li in node.children) {
          if (li.localName == 'li') {
            _processInlineChildren(li, delta);
            delta.insert('\n', {'list': 'bullet'});
          }
        }
      case 'ol':
        for (final li in node.children) {
          if (li.localName == 'li') {
            _processInlineChildren(li, delta);
            delta.insert('\n', {'list': 'ordered'});
          }
        }
      case 'img':
        final src = node.attributes['src'] ?? node.attributes['data-src'];
        if (src != null && src.isNotEmpty) {
          delta.insert({'image': src});
          delta.insert('\n');
        }
      case 'figure':
        final img = node.querySelector('img');
        if (img != null) {
          final src = img.attributes['src'] ?? img.attributes['data-src'];
          if (src != null && src.isNotEmpty) {
            delta.insert({'image': src});
            delta.insert('\n');
          }
        }
      case 'br':
        delta.insert('\n');
      case 'hr':
        delta.insert('\n');
      default:
        for (final child in node.nodes) {
          _processNode(child, delta);
        }
    }
  }

  static void _processInlineChildren(Element element, Delta delta) {
    for (final node in element.nodes) {
      _processInlineNode(node, delta, null);
    }
  }

  static void _processInlineNode(
    Node node,
    Delta delta,
    Map<String, dynamic>? inlineAttrs,
  ) {
    if (node is Text) {
      final text = node.text;
      if (text.isNotEmpty) {
        delta.insert(text, inlineAttrs);
      }
      return;
    }
    if (node is! Element) return;

    final tag = node.localName?.toLowerCase() ?? '';
    Map<String, dynamic>? newAttrs = inlineAttrs;

    switch (tag) {
      case 'strong':
      case 'b':
        newAttrs = {...?inlineAttrs, 'bold': true};
      case 'em':
      case 'i':
        newAttrs = {...?inlineAttrs, 'italic': true};
      case 'u':
        newAttrs = {...?inlineAttrs, 'underline': true};
      case 's':
      case 'del':
      case 'strike':
        newAttrs = {...?inlineAttrs, 'strike': true};
      case 'code':
        newAttrs = {...?inlineAttrs, 'code': true};
      case 'a':
        final href = node.attributes['href'];
        if (href != null && href.isNotEmpty) {
          newAttrs = {...?inlineAttrs, 'link': href};
        }
    }

    for (final child in node.nodes) {
      _processInlineNode(child, delta, newAttrs);
    }
  }

  /// 清理连续空行
  static void cleanDelta(Delta delta) {
    final ops = delta.toList();
    delta.delete(delta.length);

    var lastWasEmptyLine = false;
    for (final op in ops) {
      if (!op.isInsert) continue;
      final data = op.data;
      if (data is String && data.trim().isEmpty && data.contains('\n')) {
        if (!lastWasEmptyLine) {
          delta.insert('\n');
          lastWasEmptyLine = true;
        }
        continue;
      }
      lastWasEmptyLine = false;
      delta.insert(data, op.attributes);
    }
  }
}
