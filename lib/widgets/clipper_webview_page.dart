import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:html/parser.dart' as html_parser;
import '../services/clipper/clip_result.dart';
import '../services/web_clipper_service.dart';

/// WebView + Readability 通用剪藏页面
/// 用于 JS 渲染的页面，HTTP 提取失败时的降级方案
class ReadabilityWebViewPage extends StatefulWidget {
  final String url;

  const ReadabilityWebViewPage({super.key, required this.url});

  @override
  State<ReadabilityWebViewPage> createState() => _ReadabilityWebViewPageState();
}

class _ReadabilityWebViewPageState extends State<ReadabilityWebViewPage> {
  bool _isLoading = true;
  bool _isProcessing = false;
  String _statusText = '正在加载页面...';
  double _progress = 0;

  Timer? _loadTimeoutTimer;
  bool _completed = false;

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
    _loadTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!_completed && mounted) {
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

  /// 页面加载完成后注入 JS 提取内容
  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    if (_completed) return;
    setState(() {
      _statusText = '正在等待页面渲染...';
    });
    _loadTimeoutTimer?.cancel();

    // 延迟等待 JS 渲染完成（Bilibili 等重度 JS 页面需要时间渲染内容）
    Future.delayed(const Duration(seconds: 3), () {
      if (_completed || !mounted) return;
      setState(() {
        _isLoading = false;
        _isProcessing = true;
        _statusText = '正在提取内容...';
      });

      // 注入 JS 提取页面标题和 body innerHTML
      controller.evaluateJavascript(source: '''
        (function() {
          try {
            var title = document.title || '';
            var body = document.body ? document.body.innerHTML : '';
            var result = JSON.stringify({title: title, html: body});
            window.flutter_inappwebview.callHandler('onReadabilityData', result);
          } catch(e) {
            window.flutter_inappwebview.callHandler('onReadabilityData', '');
          }
        })();
      ''');
    });
  }

  void _onDataExtracted(List<dynamic> args) {
    if (_completed) return;

    final jsonString = args.first as String?;
    if (jsonString == null || jsonString.isEmpty) {
      _finish(ClipResult.failure('提取到的数据为空'));
      return;
    }

    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final rawHtml = data['html'] as String? ?? '';
      final title = data['title'] as String? ?? '';

      if (rawHtml.isEmpty) {
        _finish(ClipResult.failure('页面内容为空'));
        return;
      }

      // 用服务端 HTML 解析器提取正文（WebView 已渲染完成，HTML 包含完整内容）
      final document = html_parser.parse(rawHtml);
      final body = document.body;
      if (body == null) {
        _finish(ClipResult.failure('无法解析页面内容'));
        return;
      }

      WebClipperService.removeNoise(body);
      final contentDelta = WebClipperService.convertHtmlToDelta(body);

      debugPrint('ReadabilityWebView: title=$title, contentDelta.length=${contentDelta.length}, isEmpty=${contentDelta.isEmpty}');

      if (contentDelta.isEmpty) {
        _finish(ClipResult.failure('提取到的正文内容为空'));
        return;
      }

      final delta = Delta();
      if (title.isNotEmpty) {
        delta.insert(title);
        delta.insert('\n', {'header': 1});
        delta.insert(widget.url, {'link': widget.url, 'color': '#999999', 'size': 'small'});
        delta.insert('\n');
        delta.insert('\n');
      }
      for (final op in contentDelta.toList()) {
        if (op.isInsert) {
          delta.insert(op.data, op.attributes);
        }
      }

      final deltaJson = jsonEncode(delta.toJson());
      debugPrint('ReadabilityWebView: final delta length=${delta.length}, json length=${deltaJson.length}');
      debugPrint('ReadabilityWebView: delta preview=${deltaJson.length > 500 ? deltaJson.substring(0, 500) : deltaJson}');

      _finish(ClipResult.success(delta, metadata: ClipMetadata(title: title)));
    } catch (e) {
      debugPrint('ReadabilityWebViewPage: parse error=$e');
      _finish(ClipResult.failure('解析页面内容失败：$e'));
    }
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
          title: const Text('网页剪藏'),
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
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'onReadabilityData',
                  callback: _onDataExtracted,
                );
              },
              onLoadStop: _onLoadStop,
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100.0;
                });
              },
              onReceivedError: (controller, request, error) {
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
