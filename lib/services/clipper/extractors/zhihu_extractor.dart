import 'dart:convert';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import '../../web_clipper_service.dart';
import '../base_extractor.dart';
import '../extract_context.dart';
import '../webview_extractor_mixin.dart';

/// 知乎问答提取器（WebView 拦截 Feeds API）
class ZhihuExtractor extends BaseExtractor with WebViewExtractor {
  @override
  int get priority => 10;

  @override
  bool canExtract(Uri url) {
    final host = url.host;
    if (host == 'zhuanlan.zhihu.com') return false;
    if (!host.contains('zhihu.com')) return false;
    return url.pathSegments.contains('question');
  }

  @override
  String get injectedScript => '''
(function() {
  var FEEDS_PATTERN = /\\/api\\/v4\\/questions\\/\\d+\\/feeds/;

  var origXHROpen = XMLHttpRequest.prototype.open;
  var origXHRSend = XMLHttpRequest.prototype.send;

  XMLHttpRequest.prototype.open = function(method, url) {
    this.__zhihuUrl = url;
    return origXHROpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function() {
    if (this.__zhihuUrl && FEEDS_PATTERN.test(this.__zhihuUrl)) {
      this.addEventListener('load', function() {
        try {
          window.flutter_inappwebview.callHandler('onFeedsCaptured', this.responseText);
        } catch(e) {}
      });
    }
    return origXHRSend.apply(this, arguments);
  };

  var origFetch = window.fetch;
  window.fetch = function(input, init) {
    var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
    var result = origFetch.apply(this, arguments);
    if (FEEDS_PATTERN.test(url)) {
      result.then(function(resp) {
        var cloned = resp.clone();
        cloned.text().then(function(text) {
          try {
            window.flutter_inappwebview.callHandler('onFeedsCaptured', text);
          } catch(e) {}
        });
      }).catch(function(){});
    }
    return result;
  };
})();
''';

  @override
  String get handlerName => 'onFeedsCaptured';

  @override
  ClipResult parseResponse(String jsonResponse, {String? url}) {
    try {
      final parsed = _parseUrl(url ?? '');
      final json = jsonDecode(jsonResponse) as Map<String, dynamic>;
      final data = json['data'] as List?;
      if (data == null || data.isEmpty) {
        return ClipResult.failure('知乎 API 返回数据为空');
      }

      Map<String, dynamic>? target;
      if (parsed.answerId != null) {
        for (final item in data) {
          final t = item['target'] as Map<String, dynamic>?;
          if (t?['id']?.toString() == parsed.answerId) {
            target = t;
            break;
          }
        }
      }
      target ??= data[0]['target'] as Map<String, dynamic>?;

      if (target == null) {
        return ClipResult.failure('未找到目标回答');
      }

      final question = target['question'] as Map<String, dynamic>?;
      final title = question?['title'] as String? ?? '';
      final content = target['content'] as String? ?? '';

      if (content.isEmpty) {
        return ClipResult.failure('回答内容为空');
      }

      final document = html_parser.parse(content);
      final body = document.body;
      if (body == null) return ClipResult.failure('无法解析回答 HTML');

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
      debugPrint('ZhihuExtractor: parse error=$e');
      return ClipResult.failure('解析知乎数据失败：$e');
    }
  }

  @override
  Future<ClipResult> extract(ExtractContext context) async {
    // WebView 提取器不通过此方法，由 ClipperWebViewPage 直接调用 parseResponse
    return ClipResult.failure('知乎提取器需要 WebView 环境');
  }

  ({String? questionId, String? answerId}) _parseUrl(String url) {
    final uri = Uri.parse(url);
    String? questionId;
    String? answerId;

    for (int i = 0; i < uri.pathSegments.length - 1; i++) {
      if (uri.pathSegments[i] == 'question') {
        questionId = uri.pathSegments[i + 1];
      }
      if (uri.pathSegments[i] == 'answer') {
        answerId = uri.pathSegments[i + 1];
      }
    }
    return (questionId: questionId, answerId: answerId);
  }
}
