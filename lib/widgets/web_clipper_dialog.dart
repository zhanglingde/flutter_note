import 'package:flutter/material.dart';

class WebClipperDialog extends StatefulWidget {
  const WebClipperDialog({super.key});

  @override
  State<WebClipperDialog> createState() => _WebClipperDialogState();
}

class _WebClipperDialogState extends State<WebClipperDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValidUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _errorText = '请输入链接');
      return;
    }
    if (!_isValidUrl(url)) {
      setState(() => _errorText = '请输入以 http:// 或 https:// 开头的链接');
      return;
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('剪藏网页'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '输入网页链接，如 https://...',
                errorText: _errorText,
                prefixIcon: const Icon(Icons.link, size: 20),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
