import 'base_extractor.dart';
import 'clip_result.dart';

/// WebView 提取器 mixin，提供 JS 注入和回调解析能力
mixin WebViewExtractor on BaseExtractor {
  @override
  bool get requiresWebView => true;

  /// 注入到 WebView 的 JS 脚本
  String get injectedScript;

  /// Flutter 端 JavaScript 回调名称
  String get handlerName;

  /// 解析 JS 回传的数据为 ClipResult
  ClipResult parseResponse(String data, {String? url});
}
