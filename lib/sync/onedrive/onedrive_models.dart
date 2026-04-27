class OneDriveSyncConfig {
  const OneDriveSyncConfig({
    required this.clientId,
    required this.tenant,
    required this.remoteFolder,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.syncOnWrite = true,
    this.minimumSyncIntervalMinutes = 0,
    this.maxDestructiveActions = 3,
    this.syncOriginals = false,
    this.downloadOriginals = false,
    this.localOriginalRetentionDays = 30,
    this.accountName,
    this.accountEmail,
  });

  final String clientId;
  final String tenant;
  final String remoteFolder;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final bool syncOnWrite;
  final int minimumSyncIntervalMinutes;
  final int maxDestructiveActions;
  final bool syncOriginals;
  final bool downloadOriginals;
  final int localOriginalRetentionDays;
  final String? accountName;
  final String? accountEmail;

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  OneDriveSyncConfig copyWith({
    String? clientId,
    String? tenant,
    String? remoteFolder,
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    bool? syncOnWrite,
    int? minimumSyncIntervalMinutes,
    int? maxDestructiveActions,
    bool? syncOriginals,
    bool? downloadOriginals,
    int? localOriginalRetentionDays,
    String? accountName,
    String? accountEmail,
    bool clearAccountName = false,
    bool clearAccountEmail = false,
  }) {
    return OneDriveSyncConfig(
      clientId: clientId ?? this.clientId,
      tenant: tenant ?? this.tenant,
      remoteFolder: remoteFolder ?? this.remoteFolder,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      syncOnWrite: syncOnWrite ?? this.syncOnWrite,
      minimumSyncIntervalMinutes:
          minimumSyncIntervalMinutes ?? this.minimumSyncIntervalMinutes,
      maxDestructiveActions:
          maxDestructiveActions ?? this.maxDestructiveActions,
      syncOriginals: syncOriginals ?? this.syncOriginals,
      downloadOriginals: downloadOriginals ?? this.downloadOriginals,
      localOriginalRetentionDays:
          localOriginalRetentionDays ?? this.localOriginalRetentionDays,
      accountName: clearAccountName ? null : accountName ?? this.accountName,
      accountEmail: clearAccountEmail
          ? null
          : accountEmail ?? this.accountEmail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      'tenant': tenant,
      'remote_folder': remoteFolder,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_at': expiresAt.toIso8601String(),
      'sync_on_write': syncOnWrite,
      'minimum_sync_interval_minutes': minimumSyncIntervalMinutes,
      'max_destructive_actions': maxDestructiveActions,
      'sync_originals': syncOriginals,
      'download_originals': downloadOriginals,
      'local_original_retention_days': localOriginalRetentionDays,
      'account_name': accountName,
      'account_email': accountEmail,
    };
  }

  Map<String, dynamic> toStorageJson() {
    return {
      'client_id': clientId,
      'tenant': tenant,
      'remote_folder': remoteFolder,
      'expires_at': expiresAt.toIso8601String(),
      'sync_on_write': syncOnWrite,
      'minimum_sync_interval_minutes': minimumSyncIntervalMinutes,
      'max_destructive_actions': maxDestructiveActions,
      'sync_originals': syncOriginals,
      'download_originals': downloadOriginals,
      'local_original_retention_days': localOriginalRetentionDays,
      'account_name': accountName,
      'account_email': accountEmail,
    };
  }

  factory OneDriveSyncConfig.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) {
      final value = json[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return fallback;
    }

    return OneDriveSyncConfig(
      clientId: json['client_id'] as String,
      tenant: (json['tenant'] as String?) ?? 'consumers',
      remoteFolder: (json['remote_folder'] as String?) ?? 'love_diary',
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      expiresAt: DateTime.parse(json['expires_at'] as String),
      syncOnWrite: (json['sync_on_write'] as bool?) ?? true,
      minimumSyncIntervalMinutes: readInt('minimum_sync_interval_minutes', 0),
      maxDestructiveActions: readInt('max_destructive_actions', 3),
      syncOriginals: (json['sync_originals'] as bool?) ?? false,
      downloadOriginals: (json['download_originals'] as bool?) ?? false,
      localOriginalRetentionDays: readInt('local_original_retention_days', 30),
      accountName: json['account_name'] as String?,
      accountEmail: json['account_email'] as String?,
    );
  }
}

class OneDriveDeviceCodeSession {
  const OneDriveDeviceCodeSession({
    required this.clientId,
    required this.tenant,
    required this.remoteFolder,
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    this.verificationUriComplete,
    required this.message,
    required this.intervalSeconds,
    required this.expiresInSeconds,
  });

  final String clientId;
  final String tenant;
  final String remoteFolder;
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String? verificationUriComplete;
  final String message;
  final int intervalSeconds;
  final int expiresInSeconds;
}
