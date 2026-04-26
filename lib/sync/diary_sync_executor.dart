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

  int get changedCount =>
      uploadedPaths.length +
      downloadedPaths.length +
      deletedRemotePaths.length +
      deletedLocalPaths.length;
}

class SyncSafetyPolicy {
  const SyncSafetyPolicy({this.maxDestructiveActions = 3});

  final int maxDestructiveActions;
}

class SyncSafetyException implements Exception {
  const SyncSafetyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DiarySyncExecutor {
  const DiarySyncExecutor({
    required this.storage,
    required this.remoteSource,
    this.onProgress,
    this.safetyPolicy = const SyncSafetyPolicy(),
    this.attachmentPolicy = const AttachmentSyncPolicy(),
  });

  final DiaryStorage storage;
  final DiarySyncRemoteSource remoteSource;
  final void Function(double progress, String label)? onProgress;
  final SyncSafetyPolicy safetyPolicy;
  final AttachmentSyncPolicy attachmentPolicy;

  Future<SyncExecutionResult> sync() async {
    onProgress?.call(0.04, '整理本地附件');
    await storage.prepareFilesForSync();
    onProgress?.call(0.08, '读取本地和云端状态');
    final planner = DiarySyncService(
      storage: storage,
      remoteSource: remoteSource,
      attachmentPolicy: attachmentPolicy,
    );
    final plan = await planner.buildPlan();
    onProgress?.call(0.22, '生成同步计划');

    final conflictPaths = plan.actions
        .where((action) => action.type == SyncActionType.conflict)
        .map((action) => action.relativePath)
        .toList();

    if (conflictPaths.isNotEmpty) {
      onProgress?.call(1, '发现冲突，等待处理');
      return SyncExecutionResult(
        uploadedPaths: const [],
        downloadedPaths: const [],
        deletedRemotePaths: const [],
        deletedLocalPaths: const [],
        conflictPaths: conflictPaths,
      );
    }

    _enforceSafety(plan.actions);

    final uploadedPaths = <String>[];
    final downloadedPaths = <String>[];
    final deletedRemotePaths = <String>[];
    final deletedLocalPaths = <String>[];
    final localByPath = {
      for (final file in plan.localFiles) file.relativePath: file,
    };
    final sortedActions = [...plan.actions]..sort(_compareActions);

    final totalActionCount = sortedActions.isEmpty ? 1 : sortedActions.length;
    for (var index = 0; index < sortedActions.length; index++) {
      final action = sortedActions[index];
      final progress = 0.28 + ((index + 1) / totalActionCount) * 0.54;
      onProgress?.call(progress, _labelForAction(action));

      switch (action.type) {
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
        case SyncActionType.deleteLocal:
          await storage.deleteSyncFile(action.relativePath);
          deletedLocalPaths.add(action.relativePath);
          break;
        case SyncActionType.deleteRemote:
          await remoteSource.deleteFile(action.relativePath);
          deletedRemotePaths.add(action.relativePath);
          break;
        case SyncActionType.conflict:
          break;
      }
    }

    onProgress?.call(0.9, '更新同步记录');
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

      final targetAbsolutePath = await storage.resolveSyncFileAbsolutePath(
        relativePath,
      );
      await _ensureParentDirectory(targetAbsolutePath);
      await remoteSource.downloadFile(
        relativePath: relativePath,
        targetAbsolutePath: targetAbsolutePath,
        isBinary: !_isJsonPath(relativePath),
      );
    }

    await _refreshSyncState();
  }

  void _enforceSafety(List<SyncAction> actions) {
    final destructiveActions = actions
        .where(
          (action) =>
              action.type == SyncActionType.deleteRemote ||
              action.type == SyncActionType.deleteLocal,
        )
        .toList();
    if (destructiveActions.length <= safetyPolicy.maxDestructiveActions) {
      return;
    }

    throw SyncSafetyException(
      '同步计划包含 ${destructiveActions.length} 个删除动作，超过当前保护阈值 '
      '${safetyPolicy.maxDestructiveActions}。请先检查本地和云端数据，再手动放宽限制。',
    );
  }

  int _compareActions(SyncAction a, SyncAction b) {
    final typeOrder = _actionOrder(a.type).compareTo(_actionOrder(b.type));
    if (typeOrder != 0) {
      return typeOrder;
    }

    final pathOrder = _pathOrder(a).compareTo(_pathOrder(b));
    if (pathOrder != 0) {
      return pathOrder;
    }

    return a.relativePath.compareTo(b.relativePath);
  }

  int _actionOrder(SyncActionType type) {
    switch (type) {
      case SyncActionType.download:
        return 0;
      case SyncActionType.upload:
        return 1;
      case SyncActionType.deleteLocal:
        return 2;
      case SyncActionType.deleteRemote:
        return 3;
      case SyncActionType.conflict:
        return 4;
    }
  }

  int _pathOrder(SyncAction action) {
    final path = action.relativePath;

    if (action.type == SyncActionType.upload) {
      if (path.startsWith('attachments/')) {
        return 0;
      }
      if (path.startsWith('entries/')) {
        return 1;
      }
      if (path == 'profile.json') {
        return 2;
      }
      return 3;
    }

    if (action.type == SyncActionType.download) {
      if (path == 'profile.json') {
        return 0;
      }
      if (path.startsWith('entries/')) {
        return 1;
      }
      if (path.startsWith('attachments/')) {
        return 2;
      }
      return 3;
    }

    if (action.type == SyncActionType.deleteRemote ||
        action.type == SyncActionType.deleteLocal) {
      if (path.startsWith('attachments/')) {
        return 0;
      }
      if (path.startsWith('entries/')) {
        return 1;
      }
      return 2;
    }

    return 0;
  }

  String _labelForAction(SyncAction action) {
    switch (action.type) {
      case SyncActionType.download:
        return '下载 ${action.relativePath}';
      case SyncActionType.upload:
        return '上传 ${action.relativePath}';
      case SyncActionType.deleteLocal:
        return '删除本地 ${action.relativePath}';
      case SyncActionType.deleteRemote:
        return '删除云端 ${action.relativePath}';
      case SyncActionType.conflict:
        return '冲突 ${action.relativePath}';
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
    final refreshedLocalFiles = (await storage.listSyncFiles())
        .where((file) => attachmentPolicy.includeLocalPath(file.relativePath))
        .toList();
    await remoteSource.persistSnapshot(refreshedLocalFiles);
    final refreshedRemoteSnapshot = await remoteSource.fetchSnapshot();
    final refreshedRemoteFiles = refreshedRemoteSnapshot.files
        .where((file) => attachmentPolicy.includeRemotePath(file.relativePath))
        .toList();
    final refreshedState = SyncState(
      lastSyncedAt: DateTime.now(),
      lastKnownRemoteCursor: refreshedRemoteSnapshot.cursor,
      lastKnownLocalFingerprints: {
        for (final file in refreshedLocalFiles)
          file.relativePath: file.fingerprint,
      },
      lastKnownRemoteRevisions: {
        for (final file in refreshedRemoteFiles)
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
