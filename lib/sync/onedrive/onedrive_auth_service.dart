import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../data/diary_storage.dart';
import 'onedrive_models.dart';

class OneDriveAuthException implements Exception {
  const OneDriveAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OneDriveAuthService {
  const OneDriveAuthService({required this.storage});

  static const _defaultTenant = 'consumers';
  static const _defaultRemoteFolder = 'love_diary';
  static const _graphBaseUrl = 'https://graph.microsoft.com/v1.0';

  final DiaryStorage storage;

  Future<OneDriveSyncConfig?> loadConfig() async {
    return storage.loadOneDriveSyncConfig();
  }

  Future<void> disconnect() async {
    await storage.clearOneDriveSyncConfig();
  }

  Future<OneDriveDeviceCodeSession> startDeviceCodeFlow({
    required String clientId,
    String tenant = _defaultTenant,
    String remoteFolder = _defaultRemoteFolder,
  }) async {
    final response = await _postForm(
      Uri.parse(
        'https://login.microsoftonline.com/$tenant/oauth2/v2.0/devicecode',
      ),
      {
        'client_id': clientId,
        'scope':
            'offline_access Files.ReadWrite.AppFolder User.Read openid profile',
      },
    );
    final jsonMap = _decodeJson(response.body);
    _ensureSuccess(response.statusCode, jsonMap);

    return OneDriveDeviceCodeSession(
      clientId: clientId,
      tenant: tenant,
      remoteFolder: remoteFolder,
      deviceCode: jsonMap['device_code'] as String,
      userCode: jsonMap['user_code'] as String,
      verificationUri: jsonMap['verification_uri'] as String,
      verificationUriComplete: jsonMap['verification_uri_complete'] as String?,
      message: jsonMap['message'] as String,
      intervalSeconds: (jsonMap['interval'] as num?)?.toInt() ?? 5,
      expiresInSeconds: (jsonMap['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  Future<OneDriveSyncConfig> completeDeviceCodeFlow(
    OneDriveDeviceCodeSession session,
  ) async {
    final deadline = DateTime.now().add(
      Duration(seconds: session.expiresInSeconds),
    );
    var pollInterval = session.intervalSeconds;

    while (DateTime.now().isBefore(deadline)) {
      final response = await _postForm(
        Uri.parse(
          'https://login.microsoftonline.com/${session.tenant}/oauth2/v2.0/token',
        ),
        {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'client_id': session.clientId,
          'device_code': session.deviceCode,
        },
      );
      final jsonMap = _decodeJson(response.body);

      if (response.statusCode == 200) {
        final now = DateTime.now();
        final accessToken = jsonMap['access_token'] as String;
        final refreshToken = jsonMap['refresh_token'] as String? ?? '';
        final expiresIn = (jsonMap['expires_in'] as num?)?.toInt() ?? 3600;
        final profile = await _fetchProfile(accessToken);
        final config = OneDriveSyncConfig(
          clientId: session.clientId,
          tenant: session.tenant,
          remoteFolder: session.remoteFolder,
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresAt: now.add(Duration(seconds: expiresIn)),
          accountName: profile.$1,
          accountEmail: profile.$2,
        );
        await storage.saveOneDriveSyncConfig(config);
        return config;
      }

      final error = jsonMap['error'] as String?;
      if (error == 'authorization_pending') {
        await Future<void>.delayed(Duration(seconds: pollInterval));
        continue;
      }
      if (error == 'slow_down') {
        pollInterval += 5;
        await Future<void>.delayed(Duration(seconds: pollInterval));
        continue;
      }
      if (error == 'authorization_declined') {
        throw const OneDriveAuthException('OneDrive authorization was declined.');
      }
      if (error == 'expired_token') {
        throw const OneDriveAuthException('OneDrive device code expired.');
      }

      throw OneDriveAuthException(
        (jsonMap['error_description'] as String?) ??
            'OneDrive sign-in failed unexpectedly.',
      );
    }

    throw const OneDriveAuthException('Timed out waiting for OneDrive sign-in.');
  }

  Future<String> getValidAccessToken() async {
    final config = await storage.loadOneDriveSyncConfig();
    if (config == null) {
      throw const OneDriveAuthException('OneDrive is not connected yet.');
    }
    if (!config.isExpired) {
      return config.accessToken;
    }
    if (config.refreshToken.isEmpty) {
      throw const OneDriveAuthException(
        'OneDrive session expired and no refresh token is available.',
      );
    }

    final response = await _postForm(
      Uri.parse(
        'https://login.microsoftonline.com/${config.tenant}/oauth2/v2.0/token',
      ),
      {
        'grant_type': 'refresh_token',
        'client_id': config.clientId,
        'refresh_token': config.refreshToken,
        'scope':
            'offline_access Files.ReadWrite.AppFolder User.Read openid profile',
      },
    );
    final jsonMap = _decodeJson(response.body);
    _ensureSuccess(response.statusCode, jsonMap);

    final refreshedConfig = config.copyWith(
      accessToken: jsonMap['access_token'] as String,
      refreshToken: (jsonMap['refresh_token'] as String?) ?? config.refreshToken,
      expiresAt: DateTime.now().add(
        Duration(seconds: (jsonMap['expires_in'] as num?)?.toInt() ?? 3600),
      ),
    );
    await storage.saveOneDriveSyncConfig(refreshedConfig);
    return refreshedConfig.accessToken;
  }

  Future<OneDriveSyncConfig> requireConfig() async {
    final config = await storage.loadOneDriveSyncConfig();
    if (config == null) {
      throw const OneDriveAuthException('OneDrive is not connected yet.');
    }
    return config;
  }

  Future<(String?, String?)> _fetchProfile(String accessToken) async {
    try {
      final response = await _sendJsonRequest(
        uri: Uri.parse('$_graphBaseUrl/me?\$select=displayName,userPrincipalName'),
        accessToken: accessToken,
      );
      final jsonMap = _decodeJson(response.body);
      if (response.statusCode != 200) {
        return (null, null);
      }
      return (
        jsonMap['displayName'] as String?,
        jsonMap['userPrincipalName'] as String?,
      );
    } catch (_) {
      return (null, null);
    }
  }

  Future<_HttpResponseData> _postForm(
    Uri uri,
    Map<String, String> form,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: form).query);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return _HttpResponseData(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  Future<_HttpResponseData> _sendJsonRequest({
    required Uri uri,
    required String accessToken,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return _HttpResponseData(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeJson(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  void _ensureSuccess(int statusCode, Map<String, dynamic> payload) {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    throw OneDriveAuthException(
      (payload['error_description'] as String?) ??
          (payload['error'] as String?) ??
          'OneDrive request failed with status $statusCode.',
    );
  }
}

class _HttpResponseData {
  const _HttpResponseData({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
