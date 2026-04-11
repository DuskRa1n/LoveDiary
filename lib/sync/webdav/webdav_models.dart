class WebDavSyncConfig {
  const WebDavSyncConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remoteFolder,
  });

  final String serverUrl;
  final String username;
  final String password;
  final String remoteFolder;

  WebDavSyncConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? remoteFolder,
  }) {
    return WebDavSyncConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteFolder: remoteFolder ?? this.remoteFolder,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'server_url': serverUrl,
      'username': username,
      'password': password,
      'remote_folder': remoteFolder,
    };
  }

  factory WebDavSyncConfig.fromJson(Map<String, dynamic> json) {
    return WebDavSyncConfig(
      serverUrl: json['server_url'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      remoteFolder: json['remote_folder'] as String,
    );
  }
}
