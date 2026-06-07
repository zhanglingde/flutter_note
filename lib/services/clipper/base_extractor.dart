import 'clip_result.dart';
import 'extract_context.dart';

/// 提取器抽象基类
abstract class BaseExtractor {
  /// 判断是否能处理该 URL
  bool canExtract(Uri url);

  /// 执行提取
  Future<ClipResult> extract(ExtractContext context);

  /// 优先级，数字越小越优先
  int get priority;

  /// 是否需要 WebView 环境
  bool get requiresWebView => false;
}
