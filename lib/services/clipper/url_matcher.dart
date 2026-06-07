/// URL glob 模式匹配工具
class UrlMatcher {
  /// 判断 url 是否匹配 glob 模式
  /// 支持的通配符：* 匹配任意字符（不含 /），** 匹配任意字符（含 /）
  static bool matches(String url, String pattern) {
    final regex = _globToRegex(pattern);
    return regex.hasMatch(url);
  }

  static RegExp _globToRegex(String pattern) {
    final buffer = StringBuffer('^');
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          buffer.write('.*');
          i += 2;
          continue;
        }
        buffer.write('[^/]*');
      } else if (_isRegexSpecial(c)) {
        buffer.write('\\$c');
      } else {
        buffer.write(c);
      }
      i++;
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  static bool _isRegexSpecial(String c) {
    return r'\.^$+?()[]{}|'.contains(c);
  }
}
