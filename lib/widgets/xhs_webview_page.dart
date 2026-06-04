import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/web_clipper_service.dart';
import '../services/xhs_webview_service.dart';

/// 小红书 WebView 剪藏页面
class XhsWebViewPage extends StatefulWidget {
  final String url;

  const XhsWebViewPage({super.key, required this.url});

  @override
  State<XhsWebViewPage> createState() => _XhsWebViewPageState();
}

class _XhsWebViewPageState extends State<XhsWebViewPage> {
  bool _isLoading = true;
  bool _isProcessing = false;
  String _statusText = '正在加载页面...';
  double _progress = 0;

  Timer? _loadTimeoutTimer;
  bool _completed = false;
  InAppWebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _startLoadTimeout();
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    super.dispose();
  }

  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!_completed && mounted) {
        debugPrint('XhsWebView: load timeout');
        _finish(ClipResult.failure('页面加载超时'));
      }
    });
  }

  void _finish(ClipResult result) {
    if (_completed) return;
    _completed = true;
    _loadTimeoutTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  void _onDataExtracted(List<dynamic> args) {
    if (_completed) return;

    final jsonString = args.first as String?;
    if (jsonString == null || jsonString.isEmpty) {
      _finish(ClipResult.failure('提取到的数据为空'));
      return;
    }

    // 跳过登录页/通用标题的数据
    if (jsonString.contains('小红书 - 你的生活兴趣社区') ||
        jsonString.contains('"title":"小红书"')) {
      debugPrint('XhsWebView: skipping generic title data');
      return;
    }

    debugPrint('XhsWebView: data extracted');
    setState(() {
      _isProcessing = true;
      _statusText = '正在解析内容...';
    });

    final result = XhsWebViewService.parseExtractedData(jsonString, url: widget.url);
    _finish(result);
  }

  /// 当 SSR 页面的 title 出现时立即提取 meta 数据（在 JS 跳转登录页之前）
  void _onTitleChanged(String? title) {
    debugPrint('XhsWebView: title changed = $title');
    if (_completed || _controller == null) return;
    // 跳过登录页标题和无意义标题
    if (title == null ||
        title.isEmpty ||
        title == '小红书 - 你的生活兴趣社区' ||
        title == '小红书') {
      return;
    }
    // SSR 内容已就绪，立即提取数据
    debugPrint('XhsWebView: SSR title detected, extracting data NOW');
    _controller!.evaluateJavascript(
      source: XhsWebViewService.extractorScript,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_completed) {
          _finish(ClipResult.failure('用户取消了剪藏'));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('小红书剪藏'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              if (!_completed) {
                _finish(ClipResult.failure('用户取消了剪藏'));
              }
            },
          ),
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.url),
              ),
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: XhsWebViewService.extractorScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                ),
              ]),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'onXhsDataExtracted',
                  callback: _onDataExtracted,
                );
              },
              onLoadStart: (controller, url) {
                debugPrint('XhsWebView: load start $url');
              },
              onLoadStop: (controller, url) {
                debugPrint('XhsWebView: load stop $url');
              },
              onTitleChanged: (controller, title) {
                _onTitleChanged(title);
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100.0;
                });
              },
              onReceivedError: (controller, request, error) {
                debugPrint('XhsWebView: error ${error.type} ${error.description}');
                // 忽略 CONNECTION_ABORTED（由登录重定向引起）
                if (error.type == WebResourceErrorType.CONNECTION_ABORTED) {
                  return;
                }
                if (error.type == WebResourceErrorType.HOST_LOOKUP ||
                    error.type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST ||
                    error.type == WebResourceErrorType.TIMEOUT) {
                  if (!_completed) {
                    _finish(ClipResult.failure('页面加载失败：${error.description}'));
                  }
                }
              },
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                userAgent:
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',
              ),
            ),
            if (_isLoading || _isProcessing)
              Container(
                color: Colors.white,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _statusText,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        if (_isLoading) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(value: _progress),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
