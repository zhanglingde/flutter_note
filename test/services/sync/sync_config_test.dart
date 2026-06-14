import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:note/services/sync/sync_config.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('default config has sync disabled', () async {
    final config = await SyncConfig.load();
    expect(config.enabled, isFalse);
    expect(config.backendType, 'webdav');
    expect(config.webdavUrl, isEmpty);
  });

  test('save and reload preserves all fields', () async {
    final original = SyncConfig(
      enabled: true,
      backendType: 'webdav',
      webdavUrl: 'https://dav.jianguoyun.com/dav/',
      webdavUsername: 'user@example.com',
      webdavPassword: 'app-password',
      webdavRootPath: '/notes-app/',
    );
    await original.save();

    final reloaded = await SyncConfig.load();
    expect(reloaded.enabled, isTrue);
    expect(reloaded.webdavUrl, original.webdavUrl);
    expect(reloaded.webdavUsername, original.webdavUsername);
    expect(reloaded.webdavPassword, original.webdavPassword);
    expect(reloaded.webdavRootPath, original.webdavRootPath);
  });

  test('toCredentials returns Credentials from webdav fields', () async {
    final config = SyncConfig(
      enabled: true,
      backendType: 'webdav',
      webdavUrl: 'u',
      webdavUsername: 'user',
      webdavPassword: 'pwd',
      webdavRootPath: '/',
    );
    final creds = config.toCredentials();
    expect(creds.username, 'user');
    expect(creds.password, 'pwd');
  });

  test('isValid returns false when required fields missing', () {
    expect(
      SyncConfig(
        enabled: true, backendType: 'webdav',
        webdavUrl: '', webdavUsername: 'u',
        webdavPassword: 'p', webdavRootPath: '/',
      ).isValid,
      isFalse,
    );
    expect(
      SyncConfig(
        enabled: true, backendType: 'webdav',
        webdavUrl: 'u', webdavUsername: '',
        webdavPassword: 'p', webdavRootPath: '/',
      ).isValid,
      isFalse,
    );
    expect(
      SyncConfig(
        enabled: true, backendType: 'webdav',
        webdavUrl: 'u', webdavUsername: 'u',
        webdavPassword: 'p', webdavRootPath: '/',
      ).isValid,
      isTrue,
    );
  });
}
