import 'dart:convert';
import 'package:flutter/services.dart';

/// 规则模板数据模型
class ClipperRule {
  final String name;
  final String urlPattern;
  final String? title;
  final String? content;
  final List<String> exclude;
  final String? author;
  final String? published;

  const ClipperRule({
    required this.name,
    required this.urlPattern,
    this.title,
    this.content,
    this.exclude = const [],
    this.author,
    this.published,
  });

  factory ClipperRule.fromJson(Map<String, dynamic> json) {
    return ClipperRule(
      name: json['name'] as String? ?? '',
      urlPattern: json['url'] as String? ?? '',
      title: json['title'] as String?,
      content: json['content'] as String?,
      exclude: (json['exclude'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      author: json['author'] as String?,
      published: json['published'] as String?,
    );
  }
}

/// 规则模板加载器
class RuleLoader {
  static Future<List<ClipperRule>> loadRules() async {
    final rules = <ClipperRule>[];
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final rulePaths = manifest.listAssets()
          .where((p) => p.startsWith('assets/clipper_rules/') && p.endsWith('.json'))
          .toList();

      for (final path in rulePaths) {
        try {
          final jsonStr = await rootBundle.loadString(path);
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final rule = ClipperRule.fromJson(json);
          if (rule.name.isNotEmpty && rule.urlPattern.isNotEmpty) {
            rules.add(rule);
          }
        } catch (e) {
          // 跳过无效规则文件
        }
      }
    } catch (_) {}
    return rules;
  }
}
