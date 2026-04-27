import '../data/diary_storage.dart';
import 'sync_models.dart';
import 'sync_remote_source.dart';

class DiarySyncService {
  const DiarySyncService({
    required this.storage,
    required this.remoteSource,
    required this.provider,
    this.attachmentPolicy = const AttachmentSyncPolicy(),
    this.onRemoteProgress,
  });

  final DiaryStorage storage;
  final DiarySyncRemoteSource remoteSource;
  final SyncProvider provider;
  final AttachmentSyncPolicy attachmentPolicy;
  final SyncProgressCallback? onRemoteProgress;

  Future<SyncPlan> buildPlan() async {
    final localFiles = (await storage.listSyncFiles())
        .where((file) => attachmentPolicy.includeLocalPath(file.relativePath))
        .toList();
    final syncState = await storage.loadSyncState(provider);
    final tombstones = (await storage.loadTombstones())
        .where(
          (item) => attachmentPolicy.includeTombstonePath(item.relativePath),
        )
        .toList();
    final remoteSnapshot = await remoteSource.fetchSnapshot(
      baseline: syncState,
      onProgress: onRemoteProgress,
    );
    final hasUsableRemoteBaseline = syncState.hasCompleteRemoteNodeBaseline;
    final remoteFiles = remoteSnapshot.files
        .where((file) => attachmentPolicy.includeRemotePath(file.relativePath))
        .toList();

    final localByPath = {
      for (final file in localFiles) file.relativePath: file,
    };
    final remoteByPath = {
      for (final file in remoteFiles) file.relativePath: file,
    };
    final tombstonePaths = {
      for (final tombstone in tombstones) tombstone.relativePath,
    };

    final allPaths = <String>{
      ...localByPath.keys,
      ...remoteByPath.keys,
      ...tombstonePaths,
    }.toList()..sort();

    final actions = <SyncAction>[];

    for (final path in allPaths) {
      final localFile = localByPath[path];
      final remoteFile = remoteByPath[path];
      final hasTombstone = tombstonePaths.contains(path);
      final lastLocalFingerprint = hasUsableRemoteBaseline
          ? syncState.lastKnownLocalFingerprints[path]
          : null;
      final lastRemoteRevision = hasUsableRemoteBaseline
          ? syncState.lastKnownRemoteRevisions[path]
          : null;
      final hasSyncBaseline =
          lastLocalFingerprint != null || lastRemoteRevision != null;

      if (hasTombstone &&
          localFile == null &&
          (remoteFile != null || lastRemoteRevision != null)) {
        actions.add(
          SyncAction(
            type: SyncActionType.deleteRemote,
            relativePath: path,
            reason: remoteFile != null
                ? 'local_deleted_after_last_sync'
                : 'local_deleted_using_remote_baseline',
          ),
        );
        continue;
      }

      if (localFile != null && remoteFile == null) {
        final localChanged = localFile.fingerprint != lastLocalFingerprint;
        final wasSyncedBefore = lastRemoteRevision != null;

        if (wasSyncedBefore && !hasTombstone) {
          actions.add(
            SyncAction(
              type: localChanged
                  ? SyncActionType.conflict
                  : SyncActionType.deleteLocal,
              relativePath: path,
              reason: localChanged
                  ? 'remote_deleted_while_local_changed'
                  : 'remote_deleted_after_last_sync',
            ),
          );
          continue;
        }

        actions.add(
          SyncAction(
            type: SyncActionType.upload,
            relativePath: path,
            reason: 'missing_on_remote',
          ),
        );
        continue;
      }

      if (localFile == null && remoteFile != null && !hasTombstone) {
        actions.add(
          SyncAction(
            type: SyncActionType.download,
            relativePath: path,
            reason: 'missing_locally',
          ),
        );
        continue;
      }

      if (localFile == null || remoteFile == null) {
        continue;
      }

      if (!hasSyncBaseline) {
        final initialAction = _buildInitialSyncAction(
          path: path,
          localFile: localFile,
          remoteFile: remoteFile,
        );
        if (initialAction != null) {
          actions.add(initialAction);
        }
        continue;
      }

      final localChanged = localFile.fingerprint != lastLocalFingerprint;
      final remoteChanged = remoteFile.revision != lastRemoteRevision;

      if (!localChanged && !remoteChanged) {
        continue;
      }

      if (localChanged && !remoteChanged) {
        actions.add(
          SyncAction(
            type: SyncActionType.upload,
            relativePath: path,
            reason: 'local_changed',
          ),
        );
        continue;
      }

      if (!localChanged && remoteChanged) {
        actions.add(
          SyncAction(
            type: SyncActionType.download,
            relativePath: path,
            reason: 'remote_changed',
          ),
        );
        continue;
      }

      actions.add(
        SyncAction(
          type: SyncActionType.conflict,
          relativePath: path,
          reason: 'local_and_remote_changed',
        ),
      );
    }

    return SyncPlan(
      actions: actions,
      localFiles: localFiles,
      remoteFiles: remoteFiles,
    );
  }

  SyncAction? _buildInitialSyncAction({
    required String path,
    required LocalSyncFile localFile,
    required RemoteSyncFile remoteFile,
  }) {
    final sameSize = localFile.size == remoteFile.size;
    final sameType = localFile.isBinary == remoteFile.isBinary;
    final modifiedDelta = localFile.modifiedAt
        .difference(remoteFile.modifiedAt)
        .inSeconds
        .abs();

    if (sameSize && sameType && modifiedDelta <= 2) {
      return null;
    }

    if (remoteFile.modifiedAt.isAfter(localFile.modifiedAt)) {
      return SyncAction(
        type: SyncActionType.download,
        relativePath: path,
        reason: 'initial_sync_prefer_remote_newer',
      );
    }

    return SyncAction(
      type: SyncActionType.upload,
      relativePath: path,
      reason: 'initial_sync_prefer_local',
    );
  }
}
