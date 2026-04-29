enum SyncProvider {
  oneDrive('onedrive');

  const SyncProvider(this.id);

  final String id;
}

class SyncState {
  const SyncState({
    required this.lastSyncedAt,
    required this.lastKnownRemoteCursor,
    required this.lastKnownRemoteRootId,
    required this.lastKnownLocalFingerprints,
    required this.lastKnownRemoteRevisions,
    this.lastKnownRemoteNodes = const {},
    this.lastFailedAt,
    this.lastFailureMessage,
    this.incompleteSyncStartedAt,
    this.incompleteSyncActionCount = 0,
    this.incompleteSyncCompletedCount = 0,
    this.incompleteSyncLastPath,
  });

  final DateTime? lastSyncedAt;
  final String? lastKnownRemoteCursor;
  final String? lastKnownRemoteRootId;
  final Map<String, String> lastKnownLocalFingerprints;
  final Map<String, String> lastKnownRemoteRevisions;
  final Map<String, OneDriveRemoteNode> lastKnownRemoteNodes;
  final DateTime? lastFailedAt;
  final String? lastFailureMessage;
  final DateTime? incompleteSyncStartedAt;
  final int incompleteSyncActionCount;
  final int incompleteSyncCompletedCount;
  final String? incompleteSyncLastPath;

  Map<String, RemoteSyncFile> get lastKnownRemoteFiles {
    return {
      for (final node in lastKnownRemoteNodes.values)
        if (node.remoteFile != null)
          node.remoteFile!.relativePath: node.remoteFile!,
    };
  }

  bool get hasCompleteRemoteNodeBaseline {
    return (lastKnownRemoteRootId?.isNotEmpty ?? false) &&
        lastKnownRemoteNodes.isNotEmpty;
  }

  bool get hasIncompleteSync => incompleteSyncStartedAt != null;

  bool get hasUsablePlanningBaseline {
    return !hasIncompleteSync && hasCompleteRemoteNodeBaseline;
  }

  bool get canUseDelta {
    return hasUsablePlanningBaseline &&
        (lastKnownRemoteCursor?.isNotEmpty ?? false);
  }

  SyncState copyWith({
    DateTime? lastSyncedAt,
    String? lastKnownRemoteCursor,
    String? lastKnownRemoteRootId,
    Map<String, String>? lastKnownLocalFingerprints,
    Map<String, String>? lastKnownRemoteRevisions,
    Map<String, OneDriveRemoteNode>? lastKnownRemoteNodes,
    DateTime? lastFailedAt,
    String? lastFailureMessage,
    DateTime? incompleteSyncStartedAt,
    int? incompleteSyncActionCount,
    int? incompleteSyncCompletedCount,
    String? incompleteSyncLastPath,
    bool clearLastSyncedAt = false,
    bool clearLastKnownRemoteCursor = false,
    bool clearLastKnownRemoteRootId = false,
    bool clearLastFailure = false,
    bool clearIncompleteSync = false,
  }) {
    return SyncState(
      lastSyncedAt: clearLastSyncedAt
          ? null
          : lastSyncedAt ?? this.lastSyncedAt,
      lastKnownRemoteCursor: clearLastKnownRemoteCursor
          ? null
          : lastKnownRemoteCursor ?? this.lastKnownRemoteCursor,
      lastKnownRemoteRootId: clearLastKnownRemoteRootId
          ? null
          : lastKnownRemoteRootId ?? this.lastKnownRemoteRootId,
      lastKnownLocalFingerprints:
          lastKnownLocalFingerprints ?? this.lastKnownLocalFingerprints,
      lastKnownRemoteRevisions:
          lastKnownRemoteRevisions ?? this.lastKnownRemoteRevisions,
      lastKnownRemoteNodes: lastKnownRemoteNodes ?? this.lastKnownRemoteNodes,
      lastFailedAt: clearLastFailure ? null : lastFailedAt ?? this.lastFailedAt,
      lastFailureMessage: clearLastFailure
          ? null
          : lastFailureMessage ?? this.lastFailureMessage,
      incompleteSyncStartedAt: clearIncompleteSync
          ? null
          : incompleteSyncStartedAt ?? this.incompleteSyncStartedAt,
      incompleteSyncActionCount: clearIncompleteSync
          ? 0
          : incompleteSyncActionCount ?? this.incompleteSyncActionCount,
      incompleteSyncCompletedCount: clearIncompleteSync
          ? 0
          : incompleteSyncCompletedCount ?? this.incompleteSyncCompletedCount,
      incompleteSyncLastPath: clearIncompleteSync
          ? null
          : incompleteSyncLastPath ?? this.incompleteSyncLastPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'last_synced_at': lastSyncedAt?.toIso8601String(),
      'last_known_remote_cursor': lastKnownRemoteCursor,
      'last_known_remote_root_id': lastKnownRemoteRootId,
      'last_known_local_fingerprints': lastKnownLocalFingerprints,
      'last_known_remote_revisions': lastKnownRemoteRevisions,
      'last_known_remote_nodes': {
        for (final entry in lastKnownRemoteNodes.entries)
          entry.key: entry.value.toJson(),
      },
      'last_failed_at': lastFailedAt?.toIso8601String(),
      'last_failure_message': lastFailureMessage,
      'incomplete_sync_started_at': incompleteSyncStartedAt?.toIso8601String(),
      'incomplete_sync_action_count': incompleteSyncActionCount,
      'incomplete_sync_completed_count': incompleteSyncCompletedCount,
      'incomplete_sync_last_path': incompleteSyncLastPath,
    };
  }

  factory SyncState.fromJson(Map<String, dynamic> json) {
    final rawRemoteNodes = json['last_known_remote_nodes'] as Map? ?? const {};
    return SyncState(
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : DateTime.parse(json['last_synced_at'] as String),
      lastKnownRemoteCursor: json['last_known_remote_cursor'] as String?,
      lastKnownRemoteRootId: json['last_known_remote_root_id'] as String?,
      lastKnownLocalFingerprints: Map<String, String>.from(
        json['last_known_local_fingerprints'] as Map? ?? const {},
      ),
      lastKnownRemoteRevisions: Map<String, String>.from(
        json['last_known_remote_revisions'] as Map? ?? const {},
      ),
      lastKnownRemoteNodes: {
        for (final entry in rawRemoteNodes.entries)
          entry.key as String: OneDriveRemoteNode.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
      lastFailedAt: json['last_failed_at'] == null
          ? null
          : DateTime.parse(json['last_failed_at'] as String),
      lastFailureMessage: json['last_failure_message'] as String?,
      incompleteSyncStartedAt: json['incomplete_sync_started_at'] == null
          ? null
          : DateTime.parse(json['incomplete_sync_started_at'] as String),
      incompleteSyncActionCount:
          (json['incomplete_sync_action_count'] as num?)?.toInt() ?? 0,
      incompleteSyncCompletedCount:
          (json['incomplete_sync_completed_count'] as num?)?.toInt() ?? 0,
      incompleteSyncLastPath: json['incomplete_sync_last_path'] as String?,
    );
  }

  factory SyncState.initial() {
    return const SyncState(
      lastSyncedAt: null,
      lastKnownRemoteCursor: null,
      lastKnownRemoteRootId: null,
      lastKnownLocalFingerprints: {},
      lastKnownRemoteRevisions: {},
      lastKnownRemoteNodes: {},
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

  Map<String, dynamic> toJson() {
    return {
      'relative_path': relativePath,
      'revision': revision,
      'fingerprint': fingerprint,
      'modified_at': modifiedAt.toIso8601String(),
      'size': size,
      'is_binary': isBinary,
    };
  }

  factory RemoteSyncFile.fromJson(Map<String, dynamic> json) {
    return RemoteSyncFile(
      relativePath: json['relative_path'] as String,
      revision: json['revision'] as String,
      fingerprint: json['fingerprint'] as String,
      modifiedAt: DateTime.parse(json['modified_at'] as String),
      size: (json['size'] as num).toInt(),
      isBinary: json['is_binary'] as bool,
    );
  }
}

class OneDriveRemoteNode {
  const OneDriveRemoteNode({
    required this.itemId,
    required this.parentItemId,
    required this.name,
    required this.isFolder,
    required this.relativePath,
    this.revision,
    this.fingerprint,
    this.modifiedAt,
    this.size,
    this.isBinary,
  });

  final String itemId;
  final String? parentItemId;
  final String name;
  final bool isFolder;
  final String relativePath;
  final String? revision;
  final String? fingerprint;
  final DateTime? modifiedAt;
  final int? size;
  final bool? isBinary;

  RemoteSyncFile? get remoteFile {
    if (isFolder ||
        revision == null ||
        fingerprint == null ||
        modifiedAt == null ||
        size == null ||
        isBinary == null) {
      return null;
    }
    return RemoteSyncFile(
      relativePath: relativePath,
      revision: revision!,
      fingerprint: fingerprint!,
      modifiedAt: modifiedAt!,
      size: size!,
      isBinary: isBinary!,
    );
  }

  OneDriveRemoteNode copyWith({
    String? itemId,
    String? parentItemId,
    String? name,
    bool? isFolder,
    String? relativePath,
    String? revision,
    String? fingerprint,
    DateTime? modifiedAt,
    int? size,
    bool? isBinary,
    bool clearParentItemId = false,
  }) {
    return OneDriveRemoteNode(
      itemId: itemId ?? this.itemId,
      parentItemId: clearParentItemId
          ? null
          : parentItemId ?? this.parentItemId,
      name: name ?? this.name,
      isFolder: isFolder ?? this.isFolder,
      relativePath: relativePath ?? this.relativePath,
      revision: revision ?? this.revision,
      fingerprint: fingerprint ?? this.fingerprint,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      size: size ?? this.size,
      isBinary: isBinary ?? this.isBinary,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'parent_item_id': parentItemId,
      'name': name,
      'is_folder': isFolder,
      'relative_path': relativePath,
      'revision': revision,
      'fingerprint': fingerprint,
      'modified_at': modifiedAt?.toIso8601String(),
      'size': size,
      'is_binary': isBinary,
    };
  }

  factory OneDriveRemoteNode.fromJson(Map<String, dynamic> json) {
    return OneDriveRemoteNode(
      itemId: json['item_id'] as String,
      parentItemId: json['parent_item_id'] as String?,
      name: json['name'] as String? ?? '',
      isFolder: json['is_folder'] as bool? ?? false,
      relativePath: json['relative_path'] as String? ?? '',
      revision: json['revision'] as String?,
      fingerprint: json['fingerprint'] as String?,
      modifiedAt: json['modified_at'] == null
          ? null
          : DateTime.parse(json['modified_at'] as String),
      size: (json['size'] as num?)?.toInt(),
      isBinary: json['is_binary'] as bool?,
    );
  }
}

class RemoteSyncSnapshot {
  const RemoteSyncSnapshot({
    required this.cursor,
    required this.files,
    this.remoteRootId,
    this.remoteNodes = const {},
  });

  final String? cursor;
  final List<RemoteSyncFile> files;
  final String? remoteRootId;
  final Map<String, OneDriveRemoteNode> remoteNodes;
}

class SyncFilePolicy {
  const SyncFilePolicy._();

  static const profilePath = 'profile.json';
  static const schedulesPath = 'schedules.json';
  static const entriesDirectory = 'entries';
  static const attachmentsDirectory = 'attachments';
  static const originalAttachmentRole = 'originals';

  static final RegExp _safeIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,96}$');

  static bool isSyncableBusinessPath(String relativePath) {
    try {
      normalizeSyncableBusinessPath(relativePath);
      return true;
    } on FormatException {
      return false;
    }
  }

  static String normalizeSyncableBusinessPath(String relativePath) {
    final normalized = normalizeRelativePath(relativePath, allowEmpty: false);
    if (normalized == profilePath || normalized == schedulesPath) {
      return normalized;
    }

    final segments = normalized.split('/');
    if (_isEntryPath(segments) || _isAttachmentPath(segments)) {
      return normalized;
    }

    throw FormatException('Refusing non-sync business path: $relativePath');
  }

  static String normalizeRelativePath(
    String relativePath, {
    bool allowEmpty = true,
  }) {
    final normalized = relativePath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      if (allowEmpty) {
        return '';
      }
      throw const FormatException('Sync path must not be empty.');
    }
    if (_isAbsolutePath(normalized)) {
      throw FormatException('Refusing absolute sync path: $normalized');
    }

    final segments = normalized.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw FormatException('Refusing unsafe sync path: $normalized');
    }
    return segments.join('/');
  }

  static bool isSafeId(String value) {
    return _safeIdPattern.hasMatch(value);
  }

  static bool isOriginalAttachmentPath(String relativePath) {
    try {
      final normalized = normalizeRelativePath(relativePath, allowEmpty: false);
      final segments = normalized.split('/');
      return segments.length == 4 &&
          segments[0] == attachmentsDirectory &&
          segments[2] == originalAttachmentRole;
    } on FormatException {
      return false;
    }
  }

  static bool _isEntryPath(List<String> segments) {
    if (segments.length != 2 || segments[0] != entriesDirectory) {
      return false;
    }
    final fileName = segments[1];
    if (!fileName.endsWith('.json')) {
      return false;
    }
    final entryId = fileName.substring(0, fileName.length - 5);
    return isSafeId(entryId);
  }

  static bool _isAttachmentPath(List<String> segments) {
    if (segments.length != 3 && segments.length != 4) {
      return false;
    }
    if (segments[0] != attachmentsDirectory || !isSafeId(segments[1])) {
      return false;
    }
    if (segments.length == 4) {
      const roles = {'thumbnails', 'previews', originalAttachmentRole};
      if (!roles.contains(segments[2])) {
        return false;
      }
    }

    final fileName = segments.last;
    return fileName.isNotEmpty && fileName != '.' && fileName != '..';
  }

  static bool _isAbsolutePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(normalized);
  }
}

class AttachmentSyncPolicy {
  const AttachmentSyncPolicy({
    this.syncOriginals = false,
    this.downloadOriginals = false,
  });

  final bool syncOriginals;
  final bool downloadOriginals;

  bool includeLocalPath(String relativePath) {
    return SyncFilePolicy.isSyncableBusinessPath(relativePath) &&
        (!SyncFilePolicy.isOriginalAttachmentPath(relativePath) ||
            syncOriginals);
  }

  bool includeRemotePath(String relativePath) {
    return SyncFilePolicy.isSyncableBusinessPath(relativePath) &&
        (!SyncFilePolicy.isOriginalAttachmentPath(relativePath) ||
            downloadOriginals);
  }

  bool includeTombstonePath(String relativePath) {
    return SyncFilePolicy.isSyncableBusinessPath(relativePath) &&
        (!SyncFilePolicy.isOriginalAttachmentPath(relativePath) ||
            syncOriginals);
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
