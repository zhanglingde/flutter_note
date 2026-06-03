import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/web_clipper_service.dart';
import '../services/zhihu_webview_service.dart';

/// 知乎 WebView 剪藏页面
class ZhihuWebViewPage extends StatefulWidget {
  final String url;

  const ZhihuWebViewPage({super.key, required this.url});

  @override
  State<ZhihuWebViewPage> createState() => _ZhihuWebViewPageState();
}

class _ZhihuWebViewPageState extends State<ZhihuWebViewPage> {
  bool _isLoading = true;
  bool _isProcessing = false;
  String _statusText = '正在加载页面...';
  double _progress = 0;

  Timer? _loadTimeoutTimer;
  Timer? _captureTimeoutTimer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
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
        debugPrint('ZhihuWebView: load timeout');
        _finish(ClipResult.failure('页面加载超时，正在回退到通用剪藏...'));
      }
    });
  }

  void _startCaptureTimeout() {
    _captureTimeoutTimer?.cancel();
    _captureTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!_completed && mounted) {
        debugPrint('ZhihuWebView: capture timeout');
        _finish(ClipResult.failure('未捕获到知乎 API 数据，正在回退到通用剪藏...'));
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

  void _onFeedsCaptured(List<dynamic> args) {
    if (_completed) return;

    debugPrint('ZhihuWebView: feeds captured');
    setState(() {
      _isProcessing = true;
      _statusText = '正在解析内容...';
    });

    final responseText = args.first as String?;
    if (responseText == null || responseText.isEmpty) {
      _finish(ClipResult.failure('捕获到的数据为空'));
      return;
    }

    final parsed = ZhihuWebViewService.parseUrl(widget.url);
    final result = ZhihuWebViewService.parseFeedsResponse(
      responseText,
      parsed.answerId,
    );
    _finish(result);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = ZhihuWebViewService.parseUrl(widget.url);
    final questionId = parsed.questionId;

    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_completed) {
          _finish(ClipResult.failure('用户取消了剪藏'));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('知乎剪藏'),
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
                  source: ZhihuWebViewService.interceptorScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              ]),
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'onFeedsCaptured',
                  callback: _onFeedsCaptured,
                );
              },
              onLoadStart: (controller, url) {
                debugPrint('ZhihuWebView: load start $url');
              },
              onLoadStop: (controller, url) {
                debugPrint('ZhihuWebView: load stop $url');
                if (!_completed) {
                  setState(() {
                    _isLoading = false;
                    _statusText = '正在等待知乎数据加载...';
                  });
                  _loadTimeoutTimer?.cancel();
                  _startCaptureTimeout();
                }
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100.0;
                });
              },
              onReceivedError: (controller, request, error) {
                debugPrint('ZhihuWebView: error ${error.type} ${error.description}');
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
                        if (questionId != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '问题 ID: $questionId',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
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
