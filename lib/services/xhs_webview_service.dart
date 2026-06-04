import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'web_clipper_service.dart';

/// 小红书 WebView 剪藏服务
class XhsWebViewService {
  /// 注入到 WebView 的 JS 脚本：页面加载后提取 meta 标签数据
  static const String extractorScript = '''
(function() {
  if (window.__xhsClipDone) return;

  var result = {};

  var ogTitle = document.querySelector('meta[name="og:title"]');
  result.title = ogTitle ? ogTitle.getAttribute('content') : document.title;

  // 跳过登录页/通用标题
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

  /// 判断 URL 是否为小红书链接
  static bool isXiaohongshu(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.contains('xiaohongshu.com');
  }

  /// 从 JS 回传的 JSON 数据解析为 ClipResult
  static ClipResult parseExtractedData(String jsonString, {String? url}) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      String? title = (json['title'] as String?)?.trim();
      final description = (json['description'] as String?)?.trim() ?? '';
      final images = (json['images'] as List?)?.cast<String>() ?? [];

      // 去掉标题中的 " - 小红书" 后缀
      if (title != null && title.endsWith(' - 小红书')) {
        title = title.substring(0, title.length - ' - 小红书'.length);
      }

      if ((title == null || title.isEmpty) && description.isEmpty) {
        return ClipResult.failure('未能从小红书页面提取到内容');
      }

      debugPrint('XhsWebView: title=$title');
      debugPrint('XhsWebView: desc length=${description.length}');
      debugPrint('XhsWebView: images=${images.length}');

      final delta = Delta();

      // 标题
      if (title != null && title.isNotEmpty) {
        delta.insert(title, {'header': 1});
        delta.insert('\n', {'header': 1});
        if (url != null) {
          delta.insert(url, {'link': url, 'color': '#999999', 'size': 'small'});
          delta.insert('\n');
        }
      }

      // 正文
      if (description.isNotEmpty) {
        delta.insert(_formatDescription(description));
        delta.insert('\n');
      }

      // 图片
      for (final src in images) {
        delta.insert({'image': src});
        delta.insert('\n');
      }

      return ClipResult.success(delta);
    } catch (e) {
      debugPrint('XhsWebView: parse error=$e');
      return ClipResult.failure('解析小红书数据失败：$e');
    }
  }

  /// 格式化小红书正文：将 #话题# 前后加空格
  static String _formatDescription(String text) {
    return text.replaceAllMapped(
      RegExp(r'#([^#]+)#'),
      (m) => ' #${m.group(1)}',
    );
  }
}
