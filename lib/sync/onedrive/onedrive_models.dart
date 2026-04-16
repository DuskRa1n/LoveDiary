class OneDriveSyncConfig {
  const OneDriveSyncConfig({
    required this.clientId,
    required this.tenant,
    required this.remoteFolder,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.accountName,
    this.accountEmail,
  });

  final String clientId;
  final String tenant;
  final String remoteFolder;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
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
      accountName: clearAccountName ? null : accountName ?? this.accountName,
      accountEmail:
          clearAccountEmail ? null : accountEmail ?? this.accountEmail,
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
      'account_name': accountName,
      'account_email': accountEmail,
    };
  }

  factory OneDriveSyncConfig.fromJson(Map<String, dynamic> json) {
    return OneDriveSyncConfig(
      clientId: json['client_id'] as String,
      tenant: (json['tenant'] as String?) ?? 'consumers',
      remoteFolder: (json['remote_folder'] as String?) ?? 'love_diary',
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
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
