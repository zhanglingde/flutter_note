import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';

class ClipResult {
  final Delta? delta;
  final String? error;
  bool get isSuccess => delta != null;

  ClipResult.success(this.delta) : error = null;
  ClipResult.failure(this.error) : delta = null;
}

class WebClipperService {
  static const _timeout = Duration(seconds: 15);

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 各平台正文容器的 CSS 选择器（通用回退方案用）
  static const _contentSelectors = [
    '#js_content', // 微信公众号
    'article',
    '[role="main"]',
    '.post-content',
    '.entry-content',
    '.content-body',
    'main',
  ];

  /// 获取网站 favicon（PNG/JPEG 格式），返回字节数据或 null
  static Future<Uint8List?> fetchFavicon(String url) async {
    try {
      final uri = Uri.parse(url);
      final faviconUrl = Uri.https(uri.host, '/favicon.ico');
      final response = await http
          .get(faviconUrl, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 || response.bodyBytes.length < 100) {
        return null;
      }
      final bytes = response.bodyBytes;
      // 仅支持 PNG 和 JPEG（Flutter 不支持 ICO 格式）
      final isPng = bytes.length >= 4 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
      final isJpeg = bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
      if (!isPng && !isJpeg) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // 主入口：根据链接路由到不同平台的处理逻辑
  // ============================================================

  static Future<ClipResult> fetchAndConvert(String url) async {
    // 知乎问答链接：Web 平台使用 HTTP 方案，其他平台由 WebView 处理（不经过此处）
    if (_isZhihu(url) && _isZhihuQuestion(url)) {
      return _clipZhihu(url);
    }
    return _clipGeneric(url);
  }

  static bool _isZhihu(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.contains('zhihu.com');
  }

  static bool _isZhihuQuestion(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.pathSegments.contains('question');
  }

  // ============================================================
  // 知乎专用：两步请求获取内容
  // ============================================================

  static Future<ClipResult> _clipZhihu(String url) async {
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

    if (questionId == null) {
      return ClipResult.failure('无法解析知乎链接中的问题 ID');
    }

    try {
      // 第 1 步：访问 HTML 页面获取游客 Cookie
      debugPrint('WebClipper[Zhihu]: Step 1 - GET $url');
      final htmlResponse = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(_timeout);

      debugPrint(
          'WebClipper[Zhihu]: HTML status=${htmlResponse.statusCode}');

      final setCookie = htmlResponse.headers['set-cookie'] ?? '';
      debugPrint('WebClipper[Zhihu]: Set-Cookie header=$setCookie');

      // 解析 Cookie
      final cookieStr = _parseCookies(setCookie);
      debugPrint('WebClipper[Zhihu]: Parsed cookie string=$cookieStr');

      if (cookieStr.isEmpty) {
        return ClipResult.failure('未获取到知乎游客 Cookie');
      }

      // 第 2 步：用游客 Cookie 调用 Feeds API
      final apiUrl = Uri.https(
        'www.zhihu.com',
        '/api/v4/questions/$questionId/feeds',
        {
          'include':
              'data[*].is_normal,admin_closed_comment,reward_info,is_collapsed,annotation_action,annotation_detail,collapse_reason,is_sticky,collapsed_by,suggest_edit,comment_count,can_comment,content,editable_content,attachment,voteup_count,reshipment_settings,comment_permission,created_time,updated_time,review_info,relevant_info,question,excerpt,is_labeled,paid_info,paid_info_content,reaction,reaction_instruction,segment_infos,allow_segment_interaction,hot_comment,relationship.is_authorized,is_author,voting,is_thanked,is_nothelp;data[*].author.follower_count,vip_info,kvip_info,badge[*].topics;data[*].settings.table_of_content.enabled',
          'offset': '',
          'limit': '5',
          'order': 'default',
          'platform': 'desktop',
        },
      );

      debugPrint('WebClipper[Zhihu]: Step 2 - GET $apiUrl');

      final apiResponse = await http.get(apiUrl, headers: {
        'User-Agent': _headers['User-Agent']!,
        'Accept': '*/*',
        'Referer': url,
        'Cookie': cookieStr,
        'x-requested-with': 'fetch',
        'sec-fetch-site': 'same-origin',
        'sec-fetch-mode': 'cors',
      }).timeout(_timeout);

      debugPrint(
          'WebClipper[Zhihu]: API status=${apiResponse.statusCode}');

      final bodyPreview = apiResponse.body.length > 300
          ? apiResponse.body.substring(0, 300)
          : apiResponse.body;
      debugPrint('WebClipper[Zhihu]: API body(preview)=$bodyPreview');

      if (apiResponse.statusCode != 200) {
        return ClipResult.failure(
            '知乎 API 返回错误（${apiResponse.statusCode}）');
      }

      // 解析 JSON
      final json = jsonDecode(apiResponse.body) as Map<String, dynamic>;
      final data = json['data'] as List?;
      if (data == null || data.isEmpty) {
        return ClipResult.failure('知乎 API 返回数据为空');
      }

      // 查找目标回答
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

      // 提取标题、正文、来源
      final question = target['question'] as Map<String, dynamic>?;
      final title = question?['title'] as String? ?? '';
      final content = target['content'] as String? ?? '';

      if (content.isEmpty) {
        return ClipResult.failure('回答内容为空');
      }

      debugPrint('WebClipper[Zhihu]: title=$title');
      debugPrint('WebClipper[Zhihu]: content length=${content.length}');

      // 将 HTML 正文转为 Delta
      final document = html_parser.parse(content);
      final body = document.body;
      if (body == null) return ClipResult.failure('无法解析回答 HTML');

      removeNoise(body);
      final contentDelta = convertHtmlToDelta(body);

      // 组装最终 Delta：标题(H1) + 正文
      final delta = Delta();
      delta.insert(title, {'header': 1});
      delta.insert('\n', {'header': 1});
      delta.insert('\n');
      for (final op in contentDelta.toList()) {
        if (op.isInsert) {
          delta.insert(op.data, op.attributes);
        }
      }

      return ClipResult.success(delta);
    } catch (e, stack) {
      debugPrint('WebClipper[Zhihu]: Error=$e');
      debugPrint('WebClipper[Zhihu]: Stack=$stack');
      return ClipResult.failure('知乎剪藏失败：$e');
    }
  }

  /// 从 Set-Cookie 头提取 name=value 对
  static String _parseCookies(String setCookieHeader) {
    final cookies = <String, String>{};
    // 匹配 name=value 模式，排除 cookie 属性名
    const cookieAttrs = {
      'path', 'domain', 'expires', 'max-age', 'secure',
      'httponly', 'samesite', 'priority',
    };

    for (final match
        in RegExp(r'([^=;\s,]+)\s*=\s*([^;,]*)').allMatches(setCookieHeader)) {
      final name = match.group(1)?.trim() ?? '';
      final value = match.group(2)?.trim() ?? '';
      if (name.isNotEmpty && !cookieAttrs.contains(name.toLowerCase())) {
        cookies[name] = value;
      }
    }
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  // ============================================================
  // 通用方案：直接抓取 HTML + CSS 选择器提取正文
  // ============================================================

  static Future<ClipResult> _clipGeneric(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(_timeout);

      if (response.statusCode == 403 || response.statusCode == 401) {
        return ClipResult.failure('网页拒绝访问（${response.statusCode}），该站点可能不支持直接剪藏');
      }
      if (response.statusCode != 200) {
        return ClipResult.failure('网页返回错误（HTTP ${response.statusCode}）');
      }
      if (response.body.isEmpty) {
        return ClipResult.failure('网页内容为空');
      }

      final document = html_parser.parse(response.body);
      final contentElement = _findMainContent(document);
      if (contentElement == null) {
        return ClipResult.failure('无法识别网页正文区域');
      }

      removeNoise(contentElement);

      final textLength = contentElement.text.trim().length;
      if (textLength < 20) {
        return ClipResult.failure('提取到的正文内容过短（仅 $textLength 字符）');
      }

      final delta = convertHtmlToDelta(contentElement);
      if (delta.isEmpty) {
        return ClipResult.failure('转换后内容为空');
      }

      // 如果 delta 不以标题开头，提取网页标题作为 H1
      if (!_startsWithHeader(delta)) {
        final pageTitle = document.querySelector('title')?.text.trim() ??
            document
                .querySelector('meta[property="og:title"]')
                ?.attributes['content']
                ?.trim() ??
            '';
        if (pageTitle.isNotEmpty) {
          final titled = Delta();
          titled.insert(pageTitle, {'header': 1});
          titled.insert('\n', {'header': 1});
          titled.insert('\n');
          for (final op in delta.toList()) {
            if (op.isInsert) titled.insert(op.data, op.attributes);
          }
          return ClipResult.success(titled);
        }
      }

      return ClipResult.success(delta);
    } on TimeoutException {
      return ClipResult.failure('请求超时，请检查网络连接');
    } catch (e) {
      return ClipResult.failure('网络错误：$e');
    }
  }

  // ============================================================
  // 通用 HTML 解析辅助
  // ============================================================

  /// 检查 delta 是否以标题（header 属性）开头
  static bool _startsWithHeader(Delta delta) {
    for (final op in delta.toList()) {
      if (!op.isInsert) continue;
      final data = op.data;
      if (data == '\n') {
        return op.attributes?['header'] != null;
      }
      if (data is String && data.trim().isNotEmpty) {
        return false;
      }
    }
    return false;
  }

  static Element? _findMainContent(Document document) {
    for (final selector in _contentSelectors) {
      final elements = document.querySelectorAll(selector);
      if (elements.isNotEmpty) {
        Element? best;
        var maxLen = 0;
        for (final el in elements) {
          final len = el.text.length;
          if (len > maxLen) {
            maxLen = len;
            best = el;
          }
        }
        if (best != null && maxLen > 50) return best;
      }
    }

    final body = document.body;
    if (body == null) return null;

    Element? best;
    var maxLen = 0;
    for (final child in body.children) {
      if (child.localName == 'div' || child.localName == 'section') {
        final len = child.text.length;
        if (len > maxLen) {
          maxLen = len;
          best = child;
        }
      }
    }
    return best;
  }

  /// 移除 HTML 噪声元素（公开方法供其他服务复用）
  static void removeNoise(Element root) {
    const noiseSelectors = [
      'script', 'style', 'noscript', 'iframe',
      'nav', 'header', 'footer',
      '.ad', '.ads', '.advertisement',
      '.comment', '.comments',
      '.sidebar', '.widget',
      '.share', '.social-share',
      '.related', '.recommend',
      '.toolbar', '.action-bar',
      'svg',
    ];
    for (final selector in noiseSelectors) {
      root.querySelectorAll(selector).forEach((el) => el.remove());
    }
  }

  // ============================================================
  // HTML → Quill Delta 转换
  // ============================================================

  /// HTML Element → Quill Delta 转换（公开方法供其他服务复用）
  static Delta convertHtmlToDelta(Element element) {
    final delta = Delta();
    for (final node in element.nodes) {
      _processNode(node, delta);
    }
    cleanDelta(delta);
    return delta;
  }

  static void _processNode(Node node, Delta delta) {
    if (node is Text) {
      final text = node.text;
      if (text.trim().isNotEmpty) {
        delta.insert(text);
      }
      return;
    }
    if (node is! Element) return;

    final tag = node.localName?.toLowerCase() ?? '';

    switch (tag) {
      case 'h1':
        _processInlineChildren(node, delta);
        delta.insert('\n', {'header': 1});
      case 'h2':
        _processInlineChildren(node, delta);
        delta.insert('\n', {'header': 2});
      case 'h3':
      case 'h4':
        _processInlineChildren(node, delta);
        delta.insert('\n', {'header': 3});
      case 'p':
        _processInlineChildren(node, delta);
        delta.insert('\n');
      case 'blockquote':
        for (final child in node.children) {
          _processInlineChildren(child, delta);
          delta.insert('\n', {'blockquote': true});
        }
      case 'pre':
        final code = node.querySelector('code');
        final text = code?.text ?? node.text;
        if (text.isNotEmpty) {
          delta.insert('$text\n', {'code-block': true});
        }
      case 'ul':
        for (final li in node.children) {
          if (li.localName == 'li') {
            _processInlineChildren(li, delta);
            delta.insert('\n', {'list': 'bullet'});
          }
        }
      case 'ol':
        for (final li in node.children) {
          if (li.localName == 'li') {
            _processInlineChildren(li, delta);
            delta.insert('\n', {'list': 'ordered'});
          }
        }
      case 'img':
        final src = node.attributes['src'] ?? node.attributes['data-src'];
        if (src != null && src.isNotEmpty) {
          delta.insert({'image': src});
          delta.insert('\n');
        }
      case 'figure':
        final img = node.querySelector('img');
        if (img != null) {
          final src =
              img.attributes['src'] ?? img.attributes['data-src'];
          if (src != null && src.isNotEmpty) {
            delta.insert({'image': src});
            delta.insert('\n');
          }
        }
      case 'br':
        delta.insert('\n');
      case 'hr':
        delta.insert('\n');
      default:
        // div, section, article, main, span, etc.
        for (final child in node.nodes) {
          _processNode(child, delta);
        }
    }
  }

  static void _processInlineChildren(Element element, Delta delta) {
    for (final node in element.nodes) {
      _processInlineNode(node, delta, null);
    }
  }

  static void _processInlineNode(
    Node node,
    Delta delta,
    Map<String, dynamic>? inlineAttrs,
  ) {
    if (node is Text) {
      final text = node.text;
      if (text.isNotEmpty) {
        delta.insert(text, inlineAttrs);
      }
      return;
    }
    if (node is! Element) return;

    final tag = node.localName?.toLowerCase() ?? '';
    Map<String, dynamic>? newAttrs = inlineAttrs;

    switch (tag) {
      case 'strong':
      case 'b':
        newAttrs = {...?inlineAttrs, 'bold': true};
      case 'em':
      case 'i':
        newAttrs = {...?inlineAttrs, 'italic': true};
      case 'u':
        newAttrs = {...?inlineAttrs, 'underline': true};
      case 's':
      case 'del':
      case 'strike':
        newAttrs = {...?inlineAttrs, 'strike': true};
      case 'code':
        newAttrs = {...?inlineAttrs, 'code': true};
      case 'a':
        final href = node.attributes['href'];
        if (href != null && href.isNotEmpty) {
          newAttrs = {...?inlineAttrs, 'link': href};
        }
    }

    for (final child in node.nodes) {
      _processInlineNode(child, delta, newAttrs);
    }
  }

  /// 清理连续空行（公开方法供其他服务复用）
  static void cleanDelta(Delta delta) {
    final ops = delta.toList();
    delta.delete(delta.length);

    var lastWasEmptyLine = false;
    for (final op in ops) {
      if (!op.isInsert) continue;
      final data = op.data;
      if (data is String && data.trim().isEmpty && data.contains('\n')) {
        if (!lastWasEmptyLine) {
          delta.insert('\n');
          lastWasEmptyLine = true;
        }
        continue;
      }
      lastWasEmptyLine = false;
      delta.insert(data, op.attributes);
    }
  }
}
