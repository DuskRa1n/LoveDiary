class SyncState {
  const SyncState({
    required this.lastSyncedAt,
    required this.lastKnownRemoteCursor,
    required this.lastKnownLocalFingerprints,
    required this.lastKnownRemoteRevisions,
  });

  final DateTime? lastSyncedAt;
  final String? lastKnownRemoteCursor;
  final Map<String, String> lastKnownLocalFingerprints;
  final Map<String, String> lastKnownRemoteRevisions;

  SyncState copyWith({
    DateTime? lastSyncedAt,
    String? lastKnownRemoteCursor,
    Map<String, String>? lastKnownLocalFingerprints,
    Map<String, String>? lastKnownRemoteRevisions,
    bool clearLastSyncedAt = false,
    bool clearLastKnownRemoteCursor = false,
  }) {
    return SyncState(
      lastSyncedAt: clearLastSyncedAt
          ? null
          : lastSyncedAt ?? this.lastSyncedAt,
      lastKnownRemoteCursor: clearLastKnownRemoteCursor
          ? null
          : lastKnownRemoteCursor ?? this.lastKnownRemoteCursor,
      lastKnownLocalFingerprints:
          lastKnownLocalFingerprints ?? this.lastKnownLocalFingerprints,
      lastKnownRemoteRevisions:
          lastKnownRemoteRevisions ?? this.lastKnownRemoteRevisions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'last_synced_at': lastSyncedAt?.toIso8601String(),
      'last_known_remote_cursor': lastKnownRemoteCursor,
      'last_known_local_fingerprints': lastKnownLocalFingerprints,
      'last_known_remote_revisions': lastKnownRemoteRevisions,
    };
  }

  factory SyncState.fromJson(Map<String, dynamic> json) {
    return SyncState(
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : DateTime.parse(json['last_synced_at'] as String),
      lastKnownRemoteCursor: json['last_known_remote_cursor'] as String?,
      lastKnownLocalFingerprints: Map<String, String>.from(
        json['last_known_local_fingerprints'] as Map? ?? const {},
      ),
      lastKnownRemoteRevisions: Map<String, String>.from(
        json['last_known_remote_revisions'] as Map? ?? const {},
      ),
    );
  }

  factory SyncState.initial() {
    return const SyncState(
      lastSyncedAt: null,
      lastKnownRemoteCursor: null,
      lastKnownLocalFingerprints: {},
      lastKnownRemoteRevisions: {},
    );
  }
}

class SyncTombstone {
  const SyncTombstone({required this.relativePath, required this.deletedAt});

  final String relativePath;
  final DateTime deletedAt;

  Map<String, dynamic> toJson() {
    return {
      'relative_path': relativePath,
      'deleted_at': deletedAt.toIso8601String(),
    };
  }

  factory SyncTombstone.fromJson(Map<String, dynamic> json) {
    return SyncTombstone(
      relativePath: json['relative_path'] as String,
      deletedAt: DateTime.parse(json['deleted_at'] as String),
    );
  }
}

class LocalSyncFile {
  const LocalSyncFile({
    required this.relativePath,
    required this.absolutePath,
    required this.fingerprint,
    required this.modifiedAt,
    required this.size,
    required this.isBinary,
  });

  final String relativePath;
  final String absolutePath;
  final String fingerprint;
  final DateTime modifiedAt;
  final int size;
  final bool isBinary;
}

class RemoteSyncFile {
  const RemoteSyncFile({
    required this.relativePath,
    required this.revision,
    required this.fingerprint,
    required this.modifiedAt,
    required this.size,
    required this.isBinary,
  });

  final String relativePath;
  final String revision;
  final String fingerprint;
  final DateTime modifiedAt;
  final int size;
  final bool isBinary;
}

class RemoteSyncSnapshot {
  const RemoteSyncSnapshot({required this.cursor, required this.files});

  final String? cursor;
  final List<RemoteSyncFile> files;
}

class AttachmentSyncPolicy {
  const AttachmentSyncPolicy({
    this.syncOriginals = false,
    this.downloadOriginals = false,
  });

  final bool syncOriginals;
  final bool downloadOriginals;

  bool includeLocalPath(String relativePath) {
    return !_isOriginalAttachmentPath(relativePath) || syncOriginals;
  }

  bool includeRemotePath(String relativePath) {
    return !_isOriginalAttachmentPath(relativePath) || downloadOriginals;
  }

  bool includeTombstonePath(String relativePath) {
    return !_isOriginalAttachmentPath(relativePath) || syncOriginals;
  }

  bool _isOriginalAttachmentPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return normalized.startsWith('attachments/') &&
        normalized.contains('/originals/');
  }
}

enum SyncActionType { upload, download, deleteRemote, deleteLocal, conflict }

class SyncAction {
  const SyncAction({
    required this.type,
    required this.relativePath,
    this.reason,
  });

  final SyncActionType type;
  final String relativePath;
  final String? reason;
}

class SyncPlan {
  const SyncPlan({
    required this.actions,
    required this.localFiles,
    required this.remoteFiles,
  });

  final List<SyncAction> actions;
  final List<LocalSyncFile> localFiles;
  final List<RemoteSyncFile> remoteFiles;

  bool get hasConflicts =>
      actions.any((action) => action.type == SyncActionType.conflict);
}
