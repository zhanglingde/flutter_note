import 'package:flutter/material.dart';
import '../services/sync/sync_config.dart';
import '../services/sync/sync_service.dart';

class SyncSettingsScreen extends StatefulWidget {
  final SyncService syncService;
  const SyncSettingsScreen({super.key, required this.syncService});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  late SyncConfig _config;
  bool _loading = true;
  bool _testing = false;
  String? _testResult;

  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _rootCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _config = await SyncConfig.load();
    _urlCtrl.text = _config.webdavUrl;
    _userCtrl.text = _config.webdavUsername;
    _pwdCtrl.text = _config.webdavPassword;
    _rootCtrl.text = _config.webdavRootPath;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final newConfig = SyncConfig(
      enabled: _config.enabled,
      backendType: 'webdav',
      webdavUrl: _urlCtrl.text.trim(),
      webdavUsername: _userCtrl.text.trim(),
      // 密码不 trim：用户密码可能合法包含首尾空格或特殊字符。
      webdavPassword: _pwdCtrl.text,
      webdavRootPath: _rootCtrl.text.trim().isEmpty
          ? '/notes-app/'
          : _rootCtrl.text.trim(),
    );
    await newConfig.save();
    // 关键：让运行时 SyncService 实例感知新配置（baseUrl/凭据/根目录）。
    // 不调用的话，SyncService 还是用启动时固化的旧值——首次配置时 baseUrl 必然为空，
    // 后续同步会因 "No host specified in URI" 失败。
    widget.syncService.reconfigure(newConfig);
    setState(() => _config = newConfig);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    }
  }

  Future<void> _testConnection() async {
    await _save(); // 先持久化表单，确保测试当前用户输入
    if (!mounted) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      // 只做最小连通性探测，不触发完整同步（避免建目录/上传等副作用，
      // 且错误链路短，诊断更清晰）。
      await widget.syncService.testConnection();
      if (mounted) {
        setState(() => _testResult = '连接成功');
      }
    } catch (e) {
      debugPrint('[SyncSettings] 测试连接失败: $e');
      if (mounted) {
        setState(() => _testResult = '失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _syncNow() async {
    try {
      await widget.syncService.syncOnce();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败：$e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _rootCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('同步设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('启用同步'),
            value: _config.enabled,
            onChanged: (v) async {
              final newConfig = _config.copyWith(enabled: v);
              await newConfig.save();
              // 启用状态切换时也 reconfigure，保证从禁用切到启用后
              // 第一次同步立即用最新配置（无需重启应用）。
              widget.syncService.reconfigure(newConfig);
              if (mounted) {
                setState(() => _config = newConfig);
              }
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('WebDAV 配置',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'WebDAV URL（含共享路径）',
              hintText: 'http://192.168.1.10:5005/your-share/',
              helperText: '完整服务地址，含共享目录路径。例如：'
                  'http://192.168.3.60:5005/nvme12-xxx/',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              labelText: '账号',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwdCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '应用密码（非登录密码）',
              helperText: '坚果云：账户信息 → 安全选项 → 添加应用；'
                  '极空间：账号设置 → WebDAV 应用密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rootCtrl,
            decoration: const InputDecoration(
              labelText: '同步子目录（相对路径）',
              hintText: '/notes-app/',
              helperText: '在 WebDAV 服务内为笔记 App 预留的子目录。'
              '只能是相对路径，例如 /notes-app/，不要填完整 URL。',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ElevatedButton(onPressed: _save, child: const Text('保存')),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _testing ? null : _testConnection,
                child: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('测试连接'),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Text(_testResult!),
          ],
          const Divider(height: 32),
          ElevatedButton.icon(
            onPressed: _syncNow,
            icon: const Icon(Icons.sync),
            label: const Text('立即同步'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await widget.syncService.cleanupOrphanAssets();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清理本地孤儿资源')),
                );
              }
            },
            icon: const Icon(Icons.cleaning_services),
            label: const Text('清理未引用资源'),
          ),
        ],
      ),
    );
  }
}
