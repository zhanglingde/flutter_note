import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:reader_mode/reader_mode.dart';
import '../web_clipper_service.dart';
import 'base_extractor.dart';
import 'extract_context.dart';

/// Readability 通用兜底提取器
class ReadabilityExtractor extends BaseExtractor {
  @override
  int get priority => 9999;

  @override
  bool canExtract(Uri url) => true;

  @override
  Future<ClipResult> extract(ExtractContext context) async {
    final html = context.html;
    if (html == null || html.isEmpty) {
      return ClipResult.failure('无 HTML 内容');
    }

    try {
      final article = parse(html, baseUri: context.url);

      final contentHtml = article?.content;
      if (contentHtml == null || contentHtml.isEmpty) {
        return ClipResult.failure('无法提取该网页内容');
      }

      final document = html_parser.parse(contentHtml);
      final body = document.body;
      if (body == null) return ClipResult.failure('无法解析正文 HTML');

      WebClipperService.removeNoise(body);
      final contentDelta = WebClipperService.convertHtmlToDelta(body);

      if (contentDelta.isEmpty) {
        return ClipResult.failure('转换后内容为空');
      }

      final delta = _buildDelta(
        title: article?.title,
        url: context.url,
        contentDelta: contentDelta,
      );

      final metadata = _buildMetadata(article, html);

      return ClipResult.success(delta, metadata: metadata);
    } catch (e) {
      debugPrint('ReadabilityExtractor: error=$e');
      return ClipResult.failure('网页提取失败：$e');
    }
  }

  Delta _buildDelta({
    required String? title,
    required String url,
    required Delta contentDelta,
  }) {
    final delta = Delta();

    if (title != null && title.isNotEmpty) {
      delta.insert(title, {'header': 1});
      delta.insert('\n', {'header': 1});
      delta.insert(url, {'link': url, 'color': '#0000EE', 'size': '14.0'});
      delta.insert('\n');
      delta.insert('\n');
    }

    for (final op in contentDelta.toList()) {
      if (op.isInsert) {
        delta.insert(op.data, op.attributes);
      }
    }

    return delta;
  }

  ClipMetadata _buildMetadata(dynamic article, String rawHtml) {
    String? description = article?.excerpt;
    final doc = html_parser.parse(rawHtml);

    if (description == null || description.isEmpty) {
      description = doc
              .querySelector('meta[property="og:description"]')
              ?.attributes['content'] ??
          doc
              .querySelector('meta[name="description"]')
              ?.attributes['content'];
    }

    final coverImage = doc
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        doc
            .querySelector('meta[name="og:image"]')
            ?.attributes['content'];

    return ClipMetadata(
      title: article?.title,
      author: article?.byline,
      siteName: article?.siteName,
      description: description,
      coverImage: coverImage,
      published: article?.publishedTime,
    );
  }
}
