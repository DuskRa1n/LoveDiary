import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_diary/data/diary_storage.dart';
import 'package:love_diary/data/secret_store.dart';
import 'package:love_diary/sync/onedrive/onedrive_auth_service.dart';
import 'package:love_diary/sync/onedrive/onedrive_models.dart';
import 'package:love_diary/sync/sync_models.dart';

import 'test_utils.dart';

class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  late Directory tempDirectory;
  late DiaryStorage storage;
  late MemorySecretStore secretStore;
  late OneDriveAuthService authService;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'love_diary_auth_test_',
    );
    secretStore = MemorySecretStore();
    storage = DiaryStorage(
      rootDirectoryPath: tempDirectory.path,
      secretStore: secretStore,
    );
    authService = OneDriveAuthService(storage: storage);
  });

  tearDown(() async {
    await deleteTempDirectory(tempDirectory);
  });

  group('OneDriveAuthService', () {
    test('loadConfig returns null when no config exists', () async {
      final config = await authService.loadConfig();
      expect(config, isNull);
    });

    test('disconnect clears config and sync state', () async {
      // 保存一个配置
      final config = OneDriveSyncConfig(
        clientId: 'test_client_id',
        tenant: 'common',
        remoteFolder: 'test_folder',
        accessToken: 'test_access_token',
        refreshToken: 'test_refresh_token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await storage.saveOneDriveSyncConfig(config);
      await storage.saveSyncState(
        SyncState(
          lastSyncedAt: DateTime.now(),
          lastKnownRemoteCursor: 'test_cursor',
          lastKnownRemoteRootId: 'test_root_id',
          lastKnownLocalFingerprints: {},
          lastKnownRemoteRevisions: {},
        ),
        SyncProvider.oneDrive,
      );

      // 断开连接
      await authService.disconnect();

      // 验证配置已清除
      final loadedConfig = await storage.loadOneDriveSyncConfig();
      expect(loadedConfig, isNull);

      // 验证同步状态已重置
      final syncState = await storage.loadSyncState(SyncProvider.oneDrive);
      expect(syncState.lastSyncedAt, isNull);
      expect(syncState.lastKnownRemoteCursor, isNull);
    });

    test('requireConfig throws when no config exists', () async {
      expect(
        () => authService.requireConfig(),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('requireConfig returns config when exists', () async {
      final config = OneDriveSyncConfig(
        clientId: 'test_client_id',
        tenant: 'common',
        remoteFolder: 'test_folder',
        accessToken: 'test_access_token',
        refreshToken: 'test_refresh_token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await storage.saveOneDriveSyncConfig(config);

      final loadedConfig = await authService.requireConfig();
      expect(loadedConfig.clientId, equals('test_client_id'));
      expect(loadedConfig.tenant, equals('common'));
      expect(loadedConfig.remoteFolder, equals('test_folder'));
    });

    test('getValidAccessToken throws when no config exists', () async {
      expect(
        () => authService.getValidAccessToken(),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test(
      'getValidAccessToken throws when token expired and no refresh token',
      () async {
        final config = OneDriveSyncConfig(
          clientId: 'test_client_id',
          tenant: 'common',
          remoteFolder: 'test_folder',
          accessToken: 'test_access_token',
          refreshToken: '',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        );
        await storage.saveOneDriveSyncConfig(config);

        expect(
          () => authService.getValidAccessToken(),
          throwsA(isA<OneDriveAuthException>()),
        );
      },
    );

    test('getValidAccessToken returns valid token when not expired', () async {
      final config = OneDriveSyncConfig(
        clientId: 'test_client_id',
        tenant: 'common',
        remoteFolder: 'test_folder',
        accessToken: 'test_access_token',
        refreshToken: 'test_refresh_token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await storage.saveOneDriveSyncConfig(config);

      final token = await authService.getValidAccessToken();
      expect(token, equals('test_access_token'));
    });
  });
}
