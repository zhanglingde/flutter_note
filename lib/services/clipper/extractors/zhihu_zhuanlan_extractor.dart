import 'dart:convert';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import '../../web_clipper_service.dart';
import '../base_extractor.dart';
import '../extract_context.dart';
import '../webview_extractor_mixin.dart';

/// 知乎专栏文章提取器（WebView 提取 js-initialData）
class ZhihuZhuanlanExtractor extends BaseExtractor with WebViewExtractor {
  @override
  int get priority => 10;

  @override
  bool canExtract(Uri url) {
    if (url.host != 'zhuanlan.zhihu.com') return false;
    final segments = url.pathSegments;
    if (segments.isEmpty) return false;
    return segments.length >= 2 && segments[0] == 'p';
  }

  @override
  String get injectedScript => '''
(function() {
  var script = document.getElementById('js-initialData');
  if (script) {
    var title = document.title || '';
    var payload = JSON.stringify({title: title, initialData: script.textContent});
    window.flutter_inappwebview.callHandler('onZhuanlanData', payload);
  }
})();
''';

  @override
  String get handlerName => 'onZhuanlanData';

  @override
  ClipResult parseResponse(String data, {String? url}) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final title = json['title'] as String? ?? '';
      final initialDataStr = json['initialData'] as String?;
      if (initialDataStr == null || initialDataStr.isEmpty) {
        return ClipResult.failure('页面中未找到 js-initialData 数据');
      }

      final articleId = _extractArticleId(url ?? '');
      if (articleId == null) {
        return ClipResult.failure('无法从 URL 中提取文章 ID');
      }

      final initialData = jsonDecode(initialDataStr) as Map<String, dynamic>;
      final initialState = initialData['initialState'] as Map<String, dynamic>?;
      if (initialState == null) {
        return ClipResult.failure('initialData 中缺少 initialState');
      }

      final entities = initialState['entities'] as Map<String, dynamic>?;
      if (entities == null) {
        return ClipResult.failure('initialState 中缺少 entities');
      }

      final articles = entities['articles'] as Map<String, dynamic>?;
      if (articles == null) {
        return ClipResult.failure('entities 中缺少 articles');
      }

      final article = articles[articleId] as Map<String, dynamic>?;
      if (article == null) {
        return ClipResult.failure('未找到文章 ID: $articleId');
      }

      final content = article['content'] as String? ?? '';
      if (content.isEmpty) {
        return ClipResult.failure('文章内容为空');
      }

      final document = html_parser.parse(content);
      final body = document.body;
      if (body == null) return ClipResult.failure('无法解析文章 HTML');

      WebClipperService.removeNoise(body);
      final contentDelta = WebClipperService.convertHtmlToDelta(body);

      final delta = Delta();
      delta.insert(title, {'header': 1});
      delta.insert('\n', {'header': 1});
      if (url != null) {
        delta.insert(url, {'link': url, 'color': '#0000EE', 'size': '14.0'});
        delta.insert('\n');
      }
      delta.insert('\n');
      for (final op in contentDelta.toList()) {
        if (op.isInsert) {
          delta.insert(op.data, op.attributes);
        }
      }

      return ClipResult.success(delta, metadata: ClipMetadata(title: title));
    } catch (e) {
      debugPrint('ZhihuZhuanlanExtractor: parse error=$e');
      return ClipResult.failure('解析知乎专栏数据失败：$e');
    }
  }

  @override
  Future<ClipResult> extract(ExtractContext context) async {
    return ClipResult.failure('知乎专栏提取器需要 WebView 环境');
  }

  String? _extractArticleId(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'p') {
      return segments[1];
    }
    return null;
  }
}
