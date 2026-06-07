import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'base_extractor.dart';
import 'clip_result.dart';
import 'extract_context.dart';

/// 提取器注册中心
class ExtractorRegistry {
  final List<BaseExtractor> _extractors = [];

  static final ExtractorRegistry instance = ExtractorRegistry._();
  ExtractorRegistry._();

  void register(BaseExtractor extractor) {
    _extractors.add(extractor);
  }

  /// 查找匹配的提取器（含降级候选列表）
  List<BaseExtractor> _findCandidates(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return [];

    return _extractors
        .where((e) {
          if (kIsWeb && e.requiresWebView) return false;
          return e.canExtract(uri);
        })
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// 匹配最佳提取器
  BaseExtractor? match(String url) {
    final candidates = _findCandidates(url);
    return candidates.isNotEmpty ? candidates.first : null;
  }

  /// 通过 HTTP 提取（非 WebView 提取器）
  Future<ClipResult> extractViaHttp(String url) async {
    final candidates = _findCandidates(url)
        .where((e) => !e.requiresWebView)
        .toList();

    for (final extractor in candidates) {
      try {
        final html = await _fetchHtml(url);
        if (html == null) continue;

        final context = ExtractContext(
          url: url,
          html: html,
        );
        final result = await extractor.extract(context);
        if (result.isSuccess) return result;
      } catch (e) {
        debugPrint('ExtractorRegistry: ${extractor.runtimeType} failed: $e');
      }
    }

    return ClipResult.failure('无法提取该网页内容');
  }

  /// 获取 WebView 提取器（如果 URL 匹配到需要 WebView 的提取器）
  BaseExtractor? matchWebView(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || kIsWeb) return null;

    final candidates = _extractors
        .where((e) => e.requiresWebView && e.canExtract(uri))
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));

    return candidates.isNotEmpty ? candidates.first : null;
  }

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  Future<String?> _fetchHtml(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        return response.body;
      }
    } catch (_) {}
    return null;
  }
}
