import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';

/// Markdown 自动转换器
///
/// 监听 QuillController 的文本变化，检测 Markdown 语法并自动转换为富文本格式。
/// 支持的语法：标题、粗体、斜体、删除线、行内代码、列表。
class MarkdownAutoConverter {
  final QuillController controller;

  /// 是否启用自动转换
  bool enabled;

  /// 代码块语言回调（偏移量, 语言）
  final void Function(int offset, String lang)? onCodeBlockCreated;

  /// 是否正在处理中（防止递归）
  bool _isProcessing = false;

  /// 上一次的文本长度（用于检测输入方向）
  int _lastTextLength = 0;

  MarkdownAutoConverter({required this.controller, this.enabled = true, this.onCodeBlockCreated}) {
    _lastTextLength = controller.document.length;
  }

  /// Markdown 语法模式定义
  static final Map<String, RegExp> patterns = {
    // 标题：# 标题, ## 标题, ### 标题（行首匹配）
    'heading': RegExp(r'^(#{1,3})\s(.*)$'),
    // 粗体：**文本** 或 __文本__
    'bold': RegExp(r'\*\*(.+?)\*\*|__(.+?)__'),
    // 斜体：*文本* 或 _文本_（排除粗体标记）
    'italic': RegExp(
      r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)',
    ),
    // 删除线：~~文本~~
    'strikethrough': RegExp(r'~~(.+?)~~'),
    // 行内代码：`代码`
    'code': RegExp(r'`([^`]+)`'),
    // 图片：![alt](url)
    'image': RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
    // 无序列表：- 项目 或 * 项目（行首匹配）
    'bulletList': RegExp(r'^[-*]\s(.*)$'),
    // 有序列表：1. 项目（行首匹配）
    'numberList': RegExp(r'^\d+\.\s(.*)$'),
    // 代码块：``` 或 ```dart（行首匹配，回车触发）
    'codeBlock': RegExp(r'^```(\w*)\s*$'),
  };

  /// 处理文本变化事件
  ///
  /// [trigger] 触发类型：'space'（空格）、'enter'（回车）、'inline'（行内）
  void handleTextChange(String trigger) {
    if (!enabled || _isProcessing) return;

    _isProcessing = true;
    try {
      final currentLength = controller.document.length;

      // 只在文本增加时处理（忽略删除操作）
      if (currentLength > _lastTextLength) {
        switch (trigger) {
          case 'space':
            _processBlockMarkdown();
            _processInlineMarkdown();
            break;
          case 'enter':
            _processBlockMarkdown();
            break;
          case 'inline':
            _processInlineMarkdown();
            break;
        }
      }

      _lastTextLength = controller.document.length;
    } finally {
      _isProcessing = false;
    }
  }

  /// 处理块级 Markdown 语法（标题、列表）
  void _processBlockMarkdown() {
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;

    final plainText = controller.document.toPlainText();
    if (plainText.isEmpty) return;

    // 找到当前光标所在行的起始位置
    int lineStart = selection.baseOffset - 1;
    while (lineStart > 0 && plainText[lineStart - 1] != '\n') {
      lineStart--;
    }

    // 确保不越界
    if (lineStart < 0) lineStart = 0;
    int lineEnd = selection.baseOffset;
    if (lineEnd > plainText.length) lineEnd = plainText.length;

    final lineText = plainText.substring(lineStart, lineEnd);

    // 检测标题
    _convertHeading(lineText, lineStart, lineEnd);

    // 检测代码块
    _convertCodeBlock(lineText, lineStart, lineEnd);

    // 检测列表
    _convertBulletList(lineText, lineStart, lineEnd);
    _convertNumberList(lineText, lineStart, lineEnd);
  }

  /// 处理行内 Markdown 语法（粗体、斜体、删除线、代码）
  void _processInlineMarkdown() {
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;

    final plainText = controller.document.toPlainText();
    if (plainText.isEmpty) return;

    // 只检查光标前的一段文本（最多 100 个字符）
    final checkStart = (selection.baseOffset - 100).clamp(0, plainText.length);
    final checkEnd = selection.baseOffset.clamp(0, plainText.length);

    if (checkStart >= checkEnd) return;

    final textToCheck = plainText.substring(checkStart, checkEnd);

    // 检测并转换行内语法
    _convertBold(textToCheck, checkStart, checkEnd);
    _convertItalic(textToCheck, checkStart, checkEnd);
    _convertStrikethrough(textToCheck, checkStart, checkEnd);
    _convertCode(textToCheck, checkStart, checkEnd);
    _convertImage(textToCheck, checkStart, checkEnd);
  }

  /// 转换标题语法
  void _convertHeading(String lineText, int lineStart, int lineEnd) {
    final match = patterns['heading']!.firstMatch(lineText);
    if (match == null) return;

    final level = match.group(1)!.length;
    final content = match.group(2)?.trim() ?? '';

    // 确定标题级别
    Attribute? attribute;
    switch (level) {
      case 1:
        attribute = Attribute.h1;
        break;
      case 2:
        attribute = Attribute.h2;
        break;
      case 3:
        attribute = Attribute.h3;
        break;
      default:
        return;
    }

    _applyBlockConversion(
      lineStart: lineStart,
      lineEnd: lineEnd,
      newText: content,
      attribute: attribute,
    );
  }

  /// 转换无序列表语法
  void _convertBulletList(String lineText, int lineStart, int lineEnd) {
    final match = patterns['bulletList']!.firstMatch(lineText);
    if (match == null) return;

    final content = match.group(1)?.trim() ?? '';

    _applyBlockConversion(
      lineStart: lineStart,
      lineEnd: lineEnd,
      newText: content,
      attribute: Attribute.ul,
    );
  }

  /// 转换有序列表语法
  void _convertNumberList(String lineText, int lineStart, int lineEnd) {
    final match = patterns['numberList']!.firstMatch(lineText);
    if (match == null) return;

    final content = match.group(1)?.trim() ?? '';

    _applyBlockConversion(
      lineStart: lineStart,
      lineEnd: lineEnd,
      newText: content,
      attribute: Attribute.ol,
    );
  }

  /// 转换代码块语法
  ///
  /// 匹配 ``` 或 ```dart 等，删除标记行，将当前行转为代码块。
  void _convertCodeBlock(String lineText, int lineStart, int lineEnd) {
    final match = patterns['codeBlock']!.firstMatch(lineText);
    if (match == null) return;

    final lang = match.group(1)?.trim() ?? '';

    _applyBlockConversion(
      lineStart: lineStart,
      lineEnd: lineEnd,
      newText: '',
      attribute: Attribute.codeBlock,
    );

    // 通知语言信息
    if (lang.isNotEmpty && onCodeBlockCreated != null) {
      onCodeBlockCreated!(lineStart, lang);
    }
  }

  /// 转换粗体语法
  void _convertBold(String text, int textStart, int cursorPos) {
    for (final match in patterns['bold']!.allMatches(text)) {
      final content = match.group(1) ?? match.group(2) ?? '';

      final matchStart = textStart + match.start;
      final matchEnd = textStart + match.end;

      if (cursorPos < matchEnd) continue;

      _applyInlineConversion(
        start: matchStart,
        end: matchEnd,
        newText: content,
        attribute: Attribute.bold,
      );
      return; // 只转换第一个匹配
    }
  }

  /// 转换斜体语法
  void _convertItalic(String text, int textStart, int cursorPos) {
    for (final match in patterns['italic']!.allMatches(text)) {
      final content = match.group(1) ?? match.group(2) ?? '';

      final matchStart = textStart + match.start;
      final matchEnd = textStart + match.end;

      if (cursorPos < matchEnd) continue;

      _applyInlineConversion(
        start: matchStart,
        end: matchEnd,
        newText: content,
        attribute: Attribute.italic,
      );
      return; // 只转换第一个匹配
    }
  }

  /// 转换删除线语法
  void _convertStrikethrough(String text, int textStart, int cursorPos) {
    for (final match in patterns['strikethrough']!.allMatches(text)) {
      final content = match.group(1) ?? '';

      final matchStart = textStart + match.start;
      final matchEnd = textStart + match.end;

      if (cursorPos < matchEnd) continue;

      _applyInlineConversion(
        start: matchStart,
        end: matchEnd,
        newText: content,
        attribute: Attribute.strikeThrough,
      );
      return; // 只转换第一个匹配
    }
  }

  /// 转换行内代码语法
  void _convertCode(String text, int textStart, int cursorPos) {
    for (final match in patterns['code']!.allMatches(text)) {
      final content = match.group(1) ?? '';

      final matchStart = textStart + match.start;
      final matchEnd = textStart + match.end;

      if (cursorPos < matchEnd) continue;

      _applyInlineConversion(
        start: matchStart,
        end: matchEnd,
        newText: content,
        attribute: Attribute.inlineCode,
      );
      return; // 只转换第一个匹配
    }
  }

  /// 转换图片语法 ![alt](url)
  void _convertImage(String text, int textStart, int cursorPos) {
    for (final match in patterns['image']!.allMatches(text)) {
      final url = match.group(2) ?? '';
      if (url.isEmpty) continue;

      final matchStart = textStart + match.start;
      final matchEnd = textStart + match.end;

      if (cursorPos < matchEnd) continue;

      final length = matchEnd - matchStart;
      if (length <= 0) return;

      try {
        final imageData = jsonEncode({'source': url, 'width': 400});

        final delta = Delta()
          ..retain(matchStart)
          ..delete(length)
          ..insert({'image': imageData});

        final newOffset = matchStart + 1;
        final newSelection = TextSelection.collapsed(offset: newOffset);
        controller.compose(delta, newSelection, ChangeSource.local);
      } catch (e) {
        debugPrint('MarkdownAutoConverter: 图片转换失败: $e');
      }
      return;
    }
  }

  /// 应用块级转换
  void _applyBlockConversion({
    required int lineStart,
    required int lineEnd,
    required String newText,
    required Attribute attribute,
  }) {
    try {
      final length = lineEnd - lineStart;
      if (length <= 0) return;

      // 删除 Markdown 前缀
      final delta = Delta()
        ..retain(lineStart)
        ..delete(length);

      if (newText.isNotEmpty) {
        delta.insert(newText);
      }

      final newOffset = lineStart + newText.length;
      final newSelection = TextSelection.collapsed(offset: newOffset);
      controller.compose(delta, newSelection, ChangeSource.local);

      // 应用格式：有内容时格式化内容，无内容时格式化空行的 \n
      final formatLength = newText.isNotEmpty ? newText.length : 1;
      final formatDelta = Delta()
        ..retain(lineStart)
        ..retain(formatLength, attribute.toJson());

      controller.compose(formatDelta, newSelection, ChangeSource.local);
    } catch (e) {
      debugPrint('MarkdownAutoConverter: 块级转换失败: $e');
    }
  }

  /// 应用行内转换
  void _applyInlineConversion({
    required int start,
    required int end,
    required String newText,
    Attribute? attribute,
  }) {
    try {
      final length = end - start;
      if (length <= 0) return;

      // 防护：确保操作范围不跨越行边界
      final plainText = controller.document.toPlainText();
      if (start >= plainText.length || end > plainText.length) return;
      // 不允许 start 落在 \n 上，也不允许范围跨越 \n
      final rangeText = plainText.substring(start, end);
      if (rangeText.contains('\n')) return;

      // 使用 Delta 操作
      final delta = Delta()
        ..retain(start)
        ..delete(length)
        ..insert(newText);

      final newSelection = TextSelection.collapsed(offset: start + newText.length);
      controller.compose(delta, newSelection, ChangeSource.local);

      // 应用格式
      if (attribute == null) return;

      final formatDelta = Delta()
        ..retain(start)
        ..retain(newText.length, attribute.toJson());

      controller.compose(formatDelta, newSelection, ChangeSource.local);
    } catch (e) {
      debugPrint('MarkdownAutoConverter: 行内转换失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    // 清理资源
  }
}
