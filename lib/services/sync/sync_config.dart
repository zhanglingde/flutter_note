import 'package:shared_preferences/shared_preferences.dart';
import 'sync_backend.dart';

/// 同步配置
///
/// 首发仅支持 WebDAV，但 `backendType` 字段保留扩展位。
class SyncConfig {
  final bool enabled;
  final String backendType;
  final String webdavUrl;
  final String webdavUsername;
  final String webdavPassword;
  final String webdavRootPath;

  const SyncConfig({
    required this.enabled,
    required this.backendType,
    required this.webdavUrl,
    required this.webdavUsername,
    required this.webdavPassword,
    required this.webdavRootPath,
  });

  static const _kEnabled = 'sync.enabled';
  static const _kBackend = 'sync.backend_type';
  static const _kUrl = 'sync.webdav_url';
  static const _kUsername = 'sync.webdav_username';
  static const _kPassword = 'sync.webdav_password';
  static const _kRoot = 'sync.webdav_root_path';

  static Future<SyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SyncConfig(
      enabled: prefs.getBool(_kEnabled) ?? false,
      backendType: prefs.getString(_kBackend) ?? 'webdav',
      webdavUrl: prefs.getString(_kUrl) ?? '',
      webdavUsername: prefs.getString(_kUsername) ?? '',
      webdavPassword: prefs.getString(_kPassword) ?? '',
      webdavRootPath: prefs.getString(_kRoot) ?? '/notes-app/',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setString(_kBackend, backendType);
    await prefs.setString(_kUrl, webdavUrl);
    await prefs.setString(_kUsername, webdavUsername);
    await prefs.setString(_kPassword, webdavPassword);
    await prefs.setString(_kRoot, webdavRootPath);
  }

  /// 是否所有必填字段都已配置
  bool get isValid {
    return webdavUrl.isNotEmpty &&
        webdavUsername.isNotEmpty &&
        webdavPassword.isNotEmpty &&
        webdavRootPath.isNotEmpty;
  }

  /// 转换为后端凭据
  Credentials toCredentials() => Credentials(
        username: webdavUsername,
        password: webdavPassword,
      );

  SyncConfig copyWith({
    bool? enabled,
    String? backendType,
    String? webdavUrl,
    String? webdavUsername,
    String? webdavPassword,
    String? webdavRootPath,
  }) {
    return SyncConfig(
      enabled: enabled ?? this.enabled,
      backendType: backendType ?? this.backendType,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      webdavUsername: webdavUsername ?? this.webdavUsername,
      webdavPassword: webdavPassword ?? this.webdavPassword,
      webdavRootPath: webdavRootPath ?? this.webdavRootPath,
    );
  }
}
