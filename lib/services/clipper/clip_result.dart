import 'package:dart_quill_delta/dart_quill_delta.dart';

/// 网页元数据
class ClipMetadata {
  final String? title;
  final String? author;
  final String? siteName;
  final String? description;
  final String? coverImage;
  final String? published;
  final String? favicon;

  const ClipMetadata({
    this.title,
    this.author,
    this.siteName,
    this.description,
    this.coverImage,
    this.published,
    this.favicon,
  });
}

/// 剪藏结果
class ClipResult {
  final Delta? delta;
  final String? error;
  final ClipMetadata? metadata;
  bool get isSuccess => delta != null;

  ClipResult.success(this.delta, {this.metadata}) : error = null;
  ClipResult.failure(this.error) : delta = null, metadata = null;
}
