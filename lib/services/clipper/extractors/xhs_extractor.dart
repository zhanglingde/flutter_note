import 'dart:convert';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/foundation.dart';
import '../../web_clipper_service.dart';
import '../base_extractor.dart';
import '../extract_context.dart';
import '../webview_extractor_mixin.dart';

/// 小红书提取器（WebView meta 标签提取）
class XhsExtractor extends BaseExtractor with WebViewExtractor {
  @override
  int get priority => 10;

  @override
  bool canExtract(Uri url) {
    return url.host.contains('xiaohongshu.com');
  }

  @override
  String get injectedScript => '''
(function() {
  if (window.__xhsClipDone) return;

  var result = {};

  var ogTitle = document.querySelector('meta[name="og:title"]');
  result.title = ogTitle ? ogTitle.getAttribute('content') : document.title;

  if (!result.title || result.title === '小红书 - 你的生活兴趣社区' || result.title === '小红书') {
    return;
  }

  var desc = document.querySelector('meta[name="description"]');
  result.description = desc ? desc.getAttribute('content') : '';

  var images = [];
  var ogImages = document.querySelectorAll('meta[name="og:image"]');
  ogImages.forEach(function(el) {
    var src = el.getAttribute('content');
    if (src) images.push(src);
  });
  result.images = images;

  window.__xhsClipDone = true;

  if (result.title || result.description) {
    try {
      window.flutter_inappwebview.callHandler('onXhsDataExtracted', JSON.stringify(result));
    } catch(e) {}
  }
})();
''';

  @override
  String get handlerName => 'onXhsDataExtracted';

  @override
  ClipResult parseResponse(String jsonString, {String? url}) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      String? title = (json['title'] as String?)?.trim();
      final description = (json['description'] as String?)?.trim() ?? '';
      final images = (json['images'] as List?)?.cast<String>() ?? [];

      if (title != null && title.endsWith(' - 小红书')) {
        title = title.substring(0, title.length - ' - 小红书'.length);
      }

      if ((title == null || title.isEmpty) && description.isEmpty) {
        return ClipResult.failure('未能从小红书页面提取到内容');
      }

      final delta = Delta();

      if (title != null && title.isNotEmpty) {
        delta.insert(title, {'header': 1});
        delta.insert('\n', {'header': 1});
        if (url != null) {
          delta.insert(url, {'link': url, 'color': '#0000EE', 'size': '14.0'});
          delta.insert('\n');
        }
      }

      if (description.isNotEmpty) {
        delta.insert(_formatDescription(description));
        delta.insert('\n');
      }

      for (final src in images) {
        delta.insert({'image': src});
        delta.insert('\n');
      }

      return ClipResult.success(delta, metadata: ClipMetadata(title: title));
    } catch (e) {
      debugPrint('XhsExtractor: parse error=$e');
      return ClipResult.failure('解析小红书数据失败：$e');
    }
  }

  @override
  Future<ClipResult> extract(ExtractContext context) async {
    return ClipResult.failure('小红书提取器需要 WebView 环境');
  }

  String _formatDescription(String text) {
    return text.replaceAllMapped(
      RegExp(r'#([^#]+)#'),
      (m) => ' #${m.group(1)}',
    );
  }
}
