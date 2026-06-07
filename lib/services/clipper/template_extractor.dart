import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import '../web_clipper_service.dart';
import 'base_extractor.dart';
import 'extract_context.dart';
import 'template_rule.dart';
import 'url_matcher.dart';

/// 基于规则模板的提取器
class TemplateExtractor extends BaseExtractor {
  final ClipperRule rule;

  TemplateExtractor(this.rule);

  @override
  int get priority => 100; // 高于 Readability，低于专用提取器

  @override
  bool canExtract(Uri url) {
    return UrlMatcher.matches(url.toString(), rule.urlPattern);
  }

  @override
  Future<ClipResult> extract(ExtractContext context) async {
    final html = context.html;
    if (html == null || html.isEmpty) {
      return ClipResult.failure('无 HTML 内容');
    }

    try {
      final document = html_parser.parse(html);
      final delta = await _extractWithRule(document, context.url);

      if (delta == null || delta.isEmpty) {
        return ClipResult.failure('规则模板未提取到内容');
      }

      final metadata = _extractMetadata(document);
      return ClipResult.success(delta, metadata: metadata);
    } catch (e) {
      debugPrint('TemplateExtractor[${rule.name}]: error=$e');
      return ClipResult.failure('规则提取失败：$e');
    }
  }

  Future<Delta?> _extractWithRule(dynamic document, String url) async {
    final delta = Delta();

    // 提取标题
    if (rule.title != null && rule.title!.isNotEmpty) {
      final titleEl = _querySelector(document, rule.title!);
      final titleText = titleEl?.text?.trim();
      if (titleText != null && titleText.isNotEmpty) {
        delta.insert(titleText, {'header': 1});
        delta.insert('\n', {'header': 1});
        delta.insert(url, {'link': url, 'color': '#999999', 'size': 'small'});
        delta.insert('\n');
        delta.insert('\n');
      }
    }

    // 提取正文
    if (rule.content != null && rule.content!.isNotEmpty) {
      final contentEl = _querySelector(document, rule.content!);
      if (contentEl != null) {
        // 移除排除元素
        for (final excludeSelector in rule.exclude) {
          contentEl.querySelectorAll(excludeSelector).forEach((el) => el.remove());
        }

        WebClipperService.removeNoise(contentEl);
        final contentDelta = WebClipperService.convertHtmlToDelta(contentEl);
        for (final op in contentDelta.toList()) {
          if (op.isInsert) {
            delta.insert(op.data, op.attributes);
          }
        }
      }
    }

    return delta.isEmpty ? null : delta;
  }

  dynamic _querySelector(dynamic document, String selector) {
    try {
      return document.querySelector(selector);
    } catch (_) {
      return null;
    }
  }

  ClipMetadata _extractMetadata(dynamic document) {
    String? author;
    if (rule.author != null && rule.author!.isNotEmpty) {
      author = _querySelector(document, rule.author!)?.text?.trim();
    }

    String? published;
    if (rule.published != null && rule.published!.isNotEmpty) {
      final el = _querySelector(document, rule.published!);
      published = el?.attributes?['datetime'] ?? el?.text?.trim();
    }

    return ClipMetadata(
      author: author,
      published: published,
    );
  }
}
