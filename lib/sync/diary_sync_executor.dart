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
    this.onProgress,
  });

  final DiaryStorage storage;
  final DiarySyncRemoteSource remoteSource;
  final void Function(double progress, String label)? onProgress;

  Future<SyncExecutionResult> sync() async {
    onProgress?.call(0.1, '正在检查本地和云端差异');
    final planner = DiarySyncService(storage: storage, remoteSource: remoteSource);
    final plan = await planner.buildPlan();
    onProgress?.call(0.3, '同步计划已生成');

    final uploadedPaths = <String>[];
    final downloadedPaths = <String>[];
    final deletedRemotePaths = <String>[];
    final deletedLocalPaths = <String>[];
    final conflictPaths = plan.actions
        .where((action) => action.type == SyncActionType.conflict)
        .map((action) => action.relativePath)
        .toList();

    if (conflictPaths.isNotEmpty) {
      onProgress?.call(1, '发现同步冲突');
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

    final totalActionCount = sortedActions.isEmpty ? 1 : sortedActions.length;
    for (var index = 0; index < sortedActions.length; index++) {
      final action = sortedActions[index];
      final progress = 0.35 + ((index + 1) / totalActionCount) * 0.45;
      onProgress?.call(progress, _labelForAction(action));
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

    onProgress?.call(0.9, '正在刷新同步状态');
    await _refreshSyncState(deletedRemotePaths: deletedRemotePaths);
    onProgress?.call(1, '同步完成');

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

  String _labelForAction(SyncAction action) {
    switch (action.type) {
      case SyncActionType.upload:
        return '正在上传 ${action.relativePath}';
      case SyncActionType.download:
        return '正在下载 ${action.relativePath}';
      case SyncActionType.deleteRemote:
        return '正在删除云端文件 ${action.relativePath}';
      case SyncActionType.deleteLocal:
        return '正在清理本地文件 ${action.relativePath}';
      case SyncActionType.conflict:
        return '正在处理冲突 ${action.relativePath}';
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
