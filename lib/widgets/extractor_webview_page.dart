import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/clipper/clip_result.dart';
import '../services/clipper/base_extractor.dart';
import '../services/clipper/webview_extractor_mixin.dart';

/// 专用提取器的 WebView 剪藏页面（知乎/小红书等）
class ExtractorWebViewPage extends StatefulWidget {
  final String url;
  final BaseExtractor extractor;

  const ExtractorWebViewPage({
    super.key,
    required this.url,
    required this.extractor,
  });

  @override
  State<ExtractorWebViewPage> createState() => _ExtractorWebViewPageState();
}

class _ExtractorWebViewPageState extends State<ExtractorWebViewPage> {
  bool _isLoading = true;
  bool _isProcessing = false;
  String _statusText = '正在加载页面...';
  double _progress = 0;

  Timer? _loadTimeoutTimer;
  Timer? _captureTimeoutTimer;
  bool _completed = false;
  InAppWebViewController? _controller;

  late final WebViewExtractor _webViewExtractor;

  @override
  void initState() {
    super.initState();
    _webViewExtractor = widget.extractor as WebViewExtractor;
    _startLoadTimeout();
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    _captureTimeoutTimer?.cancel();
    super.dispose();
  }

  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!_completed && mounted) {
        _finish(ClipResult.failure('页面加载超时'));
      }
    });
  }

  void _startCaptureTimeout() {
    _captureTimeoutTimer?.cancel();
    _captureTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!_completed && mounted) {
        _finish(ClipResult.failure('未捕获到数据'));
      }
    });
  }

  void _finish(ClipResult result) {
    if (_completed) return;
    _completed = true;
    _loadTimeoutTimer?.cancel();
    _captureTimeoutTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  void _onDataCaptured(List<dynamic> args) {
    if (_completed) return;

    setState(() {
      _isProcessing = true;
      _statusText = '正在解析内容...';
    });

    final data = args.first as String?;
    if (data == null || data.isEmpty) {
      _finish(ClipResult.failure('捕获到的数据为空'));
      return;
    }

    final result = _webViewExtractor.parseResponse(data, url: widget.url);
    _finish(result);
  }

  @override
  Widget build(BuildContext context) {
    final injectionTime =
        _webViewExtractor.injectedScript.contains('prototype.open')
            ? UserScriptInjectionTime.AT_DOCUMENT_START
            : UserScriptInjectionTime.AT_DOCUMENT_END;

    final title = _webViewExtractor.handlerName == 'onFeedsCaptured'
        ? '知乎剪藏'
        : '网页剪藏';

    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_completed) {
          _finish(ClipResult.failure('用户取消了剪藏'));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
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
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: _webViewExtractor.injectedScript,
                  injectionTime: injectionTime,
                ),
              ]),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: _webViewExtractor.handlerName,
                  callback: _onDataCaptured,
                );
              },
              onLoadStop: (controller, url) {
                if (!_completed) {
                  setState(() {
                    _isLoading = false;
                    _statusText = '正在等待数据加载...';
                  });
                  _loadTimeoutTimer?.cancel();
                  _startCaptureTimeout();
                }
              },
              onTitleChanged: (controller, title) {
                if (title != null &&
                    title.isNotEmpty &&
                    title != '小红书 - 你的生活兴趣社区' &&
                    title != '小红书' &&
                    !_completed &&
                    _webViewExtractor.handlerName == 'onXhsDataExtracted') {
                  controller.evaluateJavascript(
                    source: _webViewExtractor.injectedScript,
                  );
                }
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100.0;
                });
              },
              onReceivedError: (controller, request, error) {
                if (error.type == WebResourceErrorType.CONNECTION_ABORTED) return;
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
