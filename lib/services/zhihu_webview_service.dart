import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'web_clipper_service.dart';

/// 知乎 WebView 剪藏服务
class ZhihuWebViewService {
  /// 注入到 WebView 的 JS 脚本：拦截 /api/v4/questions/*/feeds 响应
  static const String interceptorScript = '''
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

  /// 从 URL 中解析 questionId 和 answerId
  static ({String? questionId, String? answerId}) parseUrl(String url) {
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

  /// 判断 URL 是否为知乎问答链接（排除专栏）
  static bool isZhihuQuestion(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host;
    if (host == 'zhuanlan.zhihu.com') return false;
    if (!host.contains('zhihu.com')) return false;
    return uri.pathSegments.contains('question');
  }

  /// 从拦截到的 Feeds API JSON 响应中解析内容并转为 ClipResult
  static ClipResult parseFeedsResponse(String jsonResponse, String? answerId, {String? url}) {
    try {
      final json = jsonDecode(jsonResponse) as Map<String, dynamic>;
      final data = json['data'] as List?;
      if (data == null || data.isEmpty) {
        return ClipResult.failure('知乎 API 返回数据为空');
      }

      Map<String, dynamic>? target;
      if (answerId != null) {
        for (final item in data) {
          final t = item['target'] as Map<String, dynamic>?;
          if (t?['id']?.toString() == answerId) {
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

      debugPrint('ZhihuWebView: title=$title');
      debugPrint('ZhihuWebView: content length=${content.length}');

      final document = html_parser.parse(content);
      final body = document.body;
      if (body == null) return ClipResult.failure('无法解析回答 HTML');

      WebClipperService.removeNoise(body);
      final contentDelta = WebClipperService.convertHtmlToDelta(body);

      final delta = Delta();
      delta.insert(title, {'header': 1});
      delta.insert('\n', {'header': 1});
      if (url != null) {
        delta.insert(url, {'link': url, 'color': '#999999', 'size': 'small'});
        delta.insert('\n');
      }
      delta.insert('\n');
      for (final op in contentDelta.toList()) {
        if (op.isInsert) {
          delta.insert(op.data, op.attributes);
        }
      }

      return ClipResult.success(delta);
    } catch (e) {
      debugPrint('ZhihuWebView: parse error=$e');
      return ClipResult.failure('解析知乎数据失败：$e');
    }
  }
}
