import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../data/diary_storage.dart';
import '../../utils/app_log.dart';
import '../sync_models.dart';
import 'onedrive_models.dart';

class OneDriveAuthException implements Exception {
  const OneDriveAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OneDriveAuthService {
  OneDriveAuthService({required this.storage, Uri? authorityBaseUri})
    : _authorityBaseUri =
          authorityBaseUri ?? Uri.parse('https://login.microsoftonline.com'),
      _httpClient = HttpClient() {
    _httpClient.connectionTimeout = _requestTimeout;
    _httpClient.idleTimeout = const Duration(seconds: 30);
  }

  static const _defaultTenant = 'consumers';
  static const _defaultRemoteFolder = 'love_diary';
  static const _graphBaseUrl = 'https://graph.microsoft.com/v1.0';
  static const _graphScopes =
      'https://graph.microsoft.com/Files.ReadWrite.AppFolder '
      'https://graph.microsoft.com/User.Read '
      'offline_access openid profile';
  static const _requestTimeout = Duration(seconds: 45);
  static const invalidAccessTokenMessage = 'OneDrive 登录状态异常，请重新连接 OneDrive。';
  static const usedDeviceCodeMessage = '这个 OneDrive 验证码已经失效，请点击“重新获取验证码”后重新授权。';

  final DiaryStorage storage;
  final Uri _authorityBaseUri;
  final HttpClient _httpClient;
  Future<String>? _refreshFuture;

  static bool isMalformedAccessTokenError(String? message) {
    final value = message ?? '';
    return value.contains('IDX14100') ||
        value.contains('JWT is not well formed') ||
        value.contains('JWS or JWE Compact Serialization');
  }

  static bool isUsedDeviceCodeError(String? message) {
    final value = message ?? '';
    return value == usedDeviceCodeMessage ||
        value.contains('AADSTS70000') ||
        (value.contains('device_code') && value.contains('already been used'));
  }

  static String normalizeAuthErrorMessage(String? message, String fallback) {
    final normalized = message?.trim();
    if (isMalformedAccessTokenError(normalized)) {
      return invalidAccessTokenMessage;
    }
    if (isUsedDeviceCodeError(normalized)) {
      return usedDeviceCodeMessage;
    }
    if (normalized == null || normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }

  void dispose() {
    _httpClient.close();
  }

  Future<OneDriveSyncConfig?> loadConfig() async {
    return storage.loadOneDriveSyncConfig();
  }

  Future<void> disconnect() async {
    await storage.clearOneDriveSyncConfig();
    await storage.resetSyncState(SyncProvider.oneDrive);
  }

  Future<OneDriveDeviceCodeSession> startDeviceCodeFlow({
    required String clientId,
    String tenant = _defaultTenant,
    String remoteFolder = _defaultRemoteFolder,
  }) async {
    final response = await _postForm(
      _authorityUri(tenant, 'oauth2/v2.0/devicecode'),
      {'client_id': clientId, 'scope': _graphScopes},
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
      final response =
          await _postForm(_authorityUri(session.tenant, 'oauth2/v2.0/token'), {
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            'client_id': session.clientId,
            'device_code': session.deviceCode,
          });
      final jsonMap = _decodeJson(response.body);

      if (response.statusCode == 200) {
        final now = DateTime.now();
        final accessToken = _readRequiredToken(
          jsonMap,
          'access_token',
          'OneDrive 未返回访问令牌，请重新连接 OneDrive。',
        );
        final refreshToken = _readRequiredToken(
          jsonMap,
          'refresh_token',
          'OneDrive 未返回刷新令牌，请重新连接 OneDrive。',
        );
        final expiresIn = (jsonMap['expires_in'] as num?)?.toInt() ?? 3600;
        var config = OneDriveSyncConfig(
          clientId: session.clientId,
          tenant: session.tenant,
          remoteFolder: session.remoteFolder,
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresAt: now.add(Duration(seconds: expiresIn)),
        );
        await storage.saveOneDriveSyncConfig(config);
        final profile = await _fetchProfile(accessToken);
        if (profile.$1 != null || profile.$2 != null) {
          config = config.copyWith(
            accountName: profile.$1,
            accountEmail: profile.$2,
          );
          await storage.saveOneDriveSyncConfig(config);
        }
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
        throw const OneDriveAuthException('OneDrive 授权被拒绝。');
      }
      if (error == 'expired_token') {
        throw const OneDriveAuthException('OneDrive 设备码已过期。');
      }

      throw OneDriveAuthException(
        normalizeAuthErrorMessage(
          (jsonMap['error_description'] as String?) ??
              (jsonMap['error'] as String?),
          'OneDrive 登录出现异常。',
        ),
      );
    }

    throw const OneDriveAuthException('等待 OneDrive 登录超时。');
  }

  Future<String> getValidAccessToken({bool forceRefresh = false}) async {
    final config = await storage.loadOneDriveSyncConfig();
    if (config == null) {
      throw const OneDriveAuthException('OneDrive 尚未连接。');
    }
    final accessToken = config.accessToken.trim();
    if (!forceRefresh && !config.isExpired && accessToken.isNotEmpty) {
      return accessToken;
    }
    if (config.refreshToken.isEmpty) {
      throw const OneDriveAuthException('OneDrive 会话已过期且没有可用的刷新令牌。');
    }

    // 防止并发刷新Token
    final activeRefresh = _refreshFuture;
    if (activeRefresh != null) {
      AppLog.info('等待正在进行的Token刷新...');
      return activeRefresh;
    }

    final refreshFuture = _refreshToken(config);
    _refreshFuture = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      if (identical(_refreshFuture, refreshFuture)) {
        _refreshFuture = null;
      }
    }
  }

  Future<String> _refreshToken(OneDriveSyncConfig config) async {
    final response =
        await _postForm(_authorityUri(config.tenant, 'oauth2/v2.0/token'), {
          'grant_type': 'refresh_token',
          'client_id': config.clientId,
          'refresh_token': config.refreshToken,
          'scope': _graphScopes,
        });
    final jsonMap = _decodeJson(response.body);
    _ensureSuccess(response.statusCode, jsonMap);
    final accessToken = _readRequiredToken(
      jsonMap,
      'access_token',
      'OneDrive 未返回新的访问令牌，请重新连接 OneDrive。',
    );

    final refreshedConfig = config.copyWith(
      accessToken: accessToken,
      refreshToken:
          (jsonMap['refresh_token'] as String?) ?? config.refreshToken,
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
      throw const OneDriveAuthException('OneDrive 尚未连接。');
    }
    return config;
  }

  Future<(String?, String?)> _fetchProfile(String accessToken) async {
    try {
      final response = await _sendJsonRequest(
        uri: Uri.parse(
          '$_graphBaseUrl/me?\$select=displayName,userPrincipalName',
        ),
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
      AppLog.warn('获取OneDrive用户信息失败');
      return (null, null);
    }
  }

  Future<_HttpResponseData> _postForm(Uri uri, Map<String, String> form) async {
    try {
      final request = await _httpClient.postUrl(uri).timeout(_requestTimeout);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: form).query);
      final response = await request.close().timeout(_requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      return _HttpResponseData(statusCode: response.statusCode, body: body);
    } on TimeoutException catch (error) {
      throw OneDriveAuthException('OneDrive 授权请求超时：$error');
    }
  }

  Future<_HttpResponseData> _sendJsonRequest({
    required Uri uri,
    required String accessToken,
  }) async {
    try {
      final request = await _httpClient.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      return _HttpResponseData(statusCode: response.statusCode, body: body);
    } on TimeoutException catch (error) {
      throw OneDriveAuthException('OneDrive 用户信息请求超时：$error');
    }
  }

  Map<String, dynamic> _decodeJson(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  String _readRequiredToken(
    Map<String, dynamic> payload,
    String key,
    String message,
  ) {
    final value = (payload[key] as String?)?.trim() ?? '';
    if (value.isEmpty) {
      throw OneDriveAuthException(message);
    }
    return value;
  }

  Uri _authorityUri(String tenant, String path) {
    final baseSegments = _authorityBaseUri.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    final pathSegments = path.split('/').where((segment) => segment.isNotEmpty);
    return _authorityBaseUri.replace(
      pathSegments: [...baseSegments, tenant, ...pathSegments],
      query: null,
      fragment: null,
    );
  }

  void _ensureSuccess(int statusCode, Map<String, dynamic> payload) {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    final message =
        (payload['error_description'] as String?) ??
        (payload['error'] as String?);
    throw OneDriveAuthException(
      normalizeAuthErrorMessage(message, 'OneDrive 请求失败，状态码 $statusCode。'),
    );
  }
}

class _HttpResponseData {
  const _HttpResponseData({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
