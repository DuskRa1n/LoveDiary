import 'dart:io';

import '../data/diary_storage.dart';
import 'diary_sync_service.dart';
import 'sync_models.dart';
import 'sync_remote_source.dart';

class SyncExecutionResult {
  const SyncExecutionResult({
    required this.uploadedPaths,
    required this.downloadedPaths,
    required this.deletedRemotePaths,
    required this.deletedLocalPaths,
    required this.conflictPaths,
  });

  final List<String> uploadedPaths;
  final List<String> downloadedPaths;
  final List<String> deletedRemotePaths;
  final List<String> deletedLocalPaths;
  final List<String> conflictPaths;

  bool get hasConflicts => conflictPaths.isNotEmpty;
}

class DiarySyncExecutor {
  const DiarySyncExecutor({
    required this.storage,
    required this.remoteSource,
  });

  final DiaryStorage storage;
  final DiarySyncRemoteSource remoteSource;

  Future<SyncExecutionResult> sync() async {
    final planner = DiarySyncService(storage: storage, remoteSource: remoteSource);
    final plan = await planner.buildPlan();

    final uploadedPaths = <String>[];
    final downloadedPaths = <String>[];
    final deletedRemotePaths = <String>[];
    final deletedLocalPaths = <String>[];
    final conflictPaths = plan.actions
        .where((action) => action.type == SyncActionType.conflict)
        .map((action) => action.relativePath)
        .toList();

    if (conflictPaths.isNotEmpty) {
      return SyncExecutionResult(
        uploadedPaths: uploadedPaths,
        downloadedPaths: downloadedPaths,
        deletedRemotePaths: deletedRemotePaths,
        deletedLocalPaths: deletedLocalPaths,
        conflictPaths: conflictPaths,
      );
    }

    final localByPath = {
      for (final file in plan.localFiles) file.relativePath: file,
    };
    final sortedActions = [...plan.actions]..sort((a, b) {
      final typeOrder = _actionOrder(a.type).compareTo(_actionOrder(b.type));
      if (typeOrder != 0) {
        return typeOrder;
      }
      return a.relativePath.compareTo(b.relativePath);
    });

    for (final action in sortedActions) {
      switch (action.type) {
        case SyncActionType.upload:
          final localFile = localByPath[action.relativePath];
          if (localFile == null) {
            continue;
          }
          await remoteSource.uploadFile(
            relativePath: localFile.relativePath,
            absolutePath: localFile.absolutePath,
            isBinary: localFile.isBinary,
          );
          uploadedPaths.add(action.relativePath);
          break;
        case SyncActionType.download:
          final targetAbsolutePath = await storage.resolveSyncFileAbsolutePath(
            action.relativePath,
          );
          await _ensureParentDirectory(targetAbsolutePath);
          await remoteSource.downloadFile(
            relativePath: action.relativePath,
            targetAbsolutePath: targetAbsolutePath,
            isBinary: !_isJsonPath(action.relativePath),
          );
          downloadedPaths.add(action.relativePath);
          break;
        case SyncActionType.deleteRemote:
          await remoteSource.deleteFile(action.relativePath);
          deletedRemotePaths.add(action.relativePath);
          break;
        case SyncActionType.deleteLocal:
          await storage.deleteSyncFile(action.relativePath);
          deletedLocalPaths.add(action.relativePath);
          break;
        case SyncActionType.conflict:
          break;
      }
    }

    await _refreshSyncState(deletedRemotePaths: deletedRemotePaths);

    return SyncExecutionResult(
      uploadedPaths: uploadedPaths,
      downloadedPaths: downloadedPaths,
      deletedRemotePaths: deletedRemotePaths,
      deletedLocalPaths: deletedLocalPaths,
      conflictPaths: conflictPaths,
    );
  }

  Future<void> resolveConflicts({
    required Map<String, bool> preferLocalByPath,
  }) async {
    if (preferLocalByPath.isEmpty) {
      return;
    }

    final localFiles = await storage.listSyncFiles();
    final localByPath = {
      for (final file in localFiles) file.relativePath: file,
    };

    for (final entry in preferLocalByPath.entries) {
      final relativePath = entry.key;
      if (entry.value) {
        final localFile = localByPath[relativePath];
        if (localFile == null) {
          continue;
        }
        await remoteSource.uploadFile(
          relativePath: localFile.relativePath,
          absolutePath: localFile.absolutePath,
          isBinary: localFile.isBinary,
        );
        continue;
      }

      final targetAbsolutePath = await storage.resolveSyncFileAbsolutePath(relativePath);
      await _ensureParentDirectory(targetAbsolutePath);
      await remoteSource.downloadFile(
        relativePath: relativePath,
        targetAbsolutePath: targetAbsolutePath,
        isBinary: !_isJsonPath(relativePath),
      );
    }

    await _refreshSyncState();
  }

  int _actionOrder(SyncActionType type) {
    switch (type) {
      case SyncActionType.deleteRemote:
        return 0;
      case SyncActionType.deleteLocal:
        return 1;
      case SyncActionType.download:
        return 2;
      case SyncActionType.upload:
        return 3;
      case SyncActionType.conflict:
        return 4;
    }
  }

  bool _isJsonPath(String relativePath) {
    return relativePath.endsWith('.json');
  }

  Future<void> _ensureParentDirectory(String filePath) async {
    final file = File(filePath);
    final directory = file.parent;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  Future<void> _refreshSyncState({
    List<String> deletedRemotePaths = const [],
  }) async {
    final refreshedLocalFiles = await storage.listSyncFiles();
    await remoteSource.persistSnapshot(refreshedLocalFiles);
    final refreshedRemoteSnapshot = await remoteSource.fetchSnapshot();
    final refreshedState = SyncState(
      lastSyncedAt: DateTime.now(),
      lastKnownRemoteCursor: refreshedRemoteSnapshot.cursor,
      lastKnownLocalFingerprints: {
        for (final file in refreshedLocalFiles) file.relativePath: file.fingerprint,
      },
      lastKnownRemoteRevisions: {
        for (final file in refreshedRemoteSnapshot.files)
          file.relativePath: file.revision,
      },
    );
    await storage.saveSyncState(refreshedState);
    if (deletedRemotePaths.isNotEmpty) {
      final remainingTombstones = await storage.loadTombstones();
      final filtered = remainingTombstones
          .where((item) => !deletedRemotePaths.contains(item.relativePath))
          .toList();
      await storage.saveTombstones(filtered);
    }
  }
}
