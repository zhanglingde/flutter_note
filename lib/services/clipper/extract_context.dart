import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 提取器上下文，封装提取过程所需信息
class ExtractContext {
  final String url;
  final String? html;
  final bool isWebPlatform;
  final InAppWebViewController? webViewController;

  const ExtractContext({
    required this.url,
    this.html,
    bool? isWebPlatform,
    this.webViewController,
  }) : isWebPlatform = isWebPlatform ?? kIsWeb;
}
