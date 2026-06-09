import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_diary/data/diary_storage.dart';
import 'package:love_diary/sync/onedrive/onedrive_auth_service.dart';
import 'package:love_diary/sync/onedrive/onedrive_models.dart';
import 'package:love_diary/sync/sync_models.dart';

import 'test_utils.dart';

void main() {
  late Directory tempDirectory;
  late DiaryStorage storage;
  late MemorySecretStore secretStore;
  late OneDriveAuthService authService;
  HttpServer? tokenServer;
  StreamSubscription<HttpRequest>? tokenServerSubscription;

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
    authService.dispose();
    await tokenServerSubscription?.cancel();
    await tokenServer?.close(force: true);
    await deleteTempDirectory(tempDirectory);
  });

  Future<Uri> startTokenServer(
    Map<String, dynamic> Function(HttpRequest request, Map<String, String> form)
    handler,
  ) async {
    tokenServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tokenServerSubscription = tokenServer!.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final form = Uri.splitQueryString(body);
      final payload = handler(request, form);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
      await request.response.close();
    });
    return Uri.parse(
      'http://${tokenServer!.address.host}:${tokenServer!.port}',
    );
  }

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
      final accessToken = fakeAccessToken('cached');
      final config = OneDriveSyncConfig(
        clientId: 'test_client_id',
        tenant: 'common',
        remoteFolder: 'test_folder',
        accessToken: accessToken,
        refreshToken: 'test_refresh_token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await storage.saveOneDriveSyncConfig(config);

      final token = await authService.getValidAccessToken();
      expect(token, equals(accessToken));
    });

    test('getValidAccessToken returns opaque token when not expired', () async {
      const accessToken = 'opaque_access_token_from_provider';
      final config = OneDriveSyncConfig(
        clientId: 'test_client_id',
        tenant: 'common',
        remoteFolder: 'test_folder',
        accessToken: accessToken,
        refreshToken: 'test_refresh_token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await storage.saveOneDriveSyncConfig(config);

      final token = await authService.getValidAccessToken();
      expect(token, equals(accessToken));
    });

    test('getValidAccessToken refreshes cached token when forced', () async {
      const refreshedToken = 'new_opaque_access_token';
      final requestedPaths = <String>[];
      final submittedForms = <Map<String, String>>[];
      final authorityUri = await startTokenServer((request, form) {
        requestedPaths.add(request.uri.path);
        submittedForms.add(form);
        return {
          'access_token': refreshedToken,
          'refresh_token': 'new_refresh_token',
          'expires_in': 3600,
        };
      });
      authService.dispose();
      authService = OneDriveAuthService(
        storage: storage,
        authorityBaseUri: authorityUri,
      );
      final config = OneDriveSyncConfig(
        clientId: 'test_client_id',
        tenant: 'common',
        remoteFolder: 'test_folder',
        accessToken: 'old_access_token',
        refreshToken: 'old_refresh_token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await storage.saveOneDriveSyncConfig(config);

      final token = await authService.getValidAccessToken(forceRefresh: true);
      final savedConfig = await storage.loadOneDriveSyncConfig();

      expect(token, equals(refreshedToken));
      expect(savedConfig?.accessToken, equals(refreshedToken));
      expect(savedConfig?.refreshToken, equals('new_refresh_token'));
      expect(requestedPaths, equals(['/common/oauth2/v2.0/token']));
      expect(submittedForms.single['grant_type'], equals('refresh_token'));
      expect(submittedForms.single['client_id'], equals('test_client_id'));
      expect(
        submittedForms.single['refresh_token'],
        equals('old_refresh_token'),
      );
    });

    test('normalizes malformed JWT error message', () {
      final message = OneDriveAuthService.normalizeAuthErrorMessage(
        'IDX14100: JWT is not well formed, there are no dots (.).',
        'fallback',
      );

      expect(message, equals(OneDriveAuthService.invalidAccessTokenMessage));
    });

    test('normalizes used device code error message', () {
      final message = OneDriveAuthService.normalizeAuthErrorMessage(
        'AADSTS70000: The provided value for the input parameter '
            'device_code has already been used.',
        'fallback',
      );

      expect(message, equals(OneDriveAuthService.usedDeviceCodeMessage));
    });
  });
}

String fakeAccessToken(String subject) {
  String segment(Object value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return [
    segment({'alg': 'none', 'typ': 'JWT'}),
    segment({'sub': subject}),
    segment({'sig': 'test'}),
  ].join('.');
}
