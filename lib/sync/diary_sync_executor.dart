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

class _SyncActionSummary {
  const _SyncActionSummary({
    required this.uploads,
    required this.downloads,
    required this.remoteDeletes,
    required this.localDeletes,
    required this.conflicts,
  });

  final int uploads;
  final int downloads;
  final int remoteDeletes;
  final int localDeletes;
  final int conflicts;

  int get total =>
      uploads + downloads + remoteDeletes + localDeletes + conflicts;

  String get description {
    if (total == 0) {
      return '没有变更';
    }
    return '上传 $uploads，下载 $downloads，云端删除 $remoteDeletes，本地删除 $localDeletes，冲突 $conflicts';
  }

  factory _SyncActionSummary.fromActions(List<SyncAction> actions) {
    var uploads = 0;
    var downloads = 0;
    var remoteDeletes = 0;
    var localDeletes = 0;
    var conflicts = 0;
    for (final action in actions) {
      switch (action.type) {
        case SyncActionType.upload:
          uploads++;
          break;
        case SyncActionType.download:
          downloads++;
          break;
        case SyncActionType.deleteRemote:
          remoteDeletes++;
          break;
        case SyncActionType.deleteLocal:
          localDeletes++;
          break;
        case SyncActionType.conflict:
          conflicts++;
          break;
      }
    }
    return _SyncActionSummary(
      uploads: uploads,
      downloads: downloads,
      remoteDeletes: remoteDeletes,
      localDeletes: localDeletes,
      conflicts: conflicts,
    );
  }
}

class DiarySyncExecutor {
  const DiarySyncExecutor({
    required this.storage,
    required this.remoteSource,
    required this.provider,
    this.onProgress,
    this.safetyPolicy = const SyncSafetyPolicy(),
    this.attachmentPolicy = const AttachmentSyncPolicy(),
  });

  final DiaryStorage storage;
  final DiarySyncRemoteSource remoteSource;
  final SyncProvider provider;
  final void Function(double progress, String label)? onProgress;
  final SyncSafetyPolicy safetyPolicy;
  final AttachmentSyncPolicy attachmentPolicy;

  Future<SyncExecutionResult> sync() async {
    onProgress?.call(0.04, '准备同步：整理本地附件');
    await _yieldToEventLoop();
    await storage.prepareFilesForSync();
    onProgress?.call(0.08, '扫描状态：读取本地文件和 OneDrive 变更');
    await _yieldToEventLoop();
    final planner = DiarySyncService(
      storage: storage,
      remoteSource: remoteSource,
      provider: provider,
      attachmentPolicy: attachmentPolicy,
      onRemoteProgress: (remoteProgress, label) {
        final mappedProgress = 0.08 + remoteProgress.clamp(0, 1) * 0.12;
        onProgress?.call(mappedProgress, label);
      },
    );
    final plan = await planner.buildPlan();
    final sortedActions = [...plan.actions]..sort(_compareActions);
    final summary = _SyncActionSummary.fromActions(sortedActions);
    onProgress?.call(
      0.22,
      '计划完成：本地 ${plan.localFiles.length} 个，云端 ${plan.remoteFiles.length} 个；${summary.description}',
    );
    await _yieldToEventLoop();

    final conflictPaths = sortedActions
        .where((action) => action.type == SyncActionType.conflict)
        .map((action) => action.relativePath)
        .toList();

    if (conflictPaths.isNotEmpty) {
      onProgress?.call(1, '发现 ${conflictPaths.length} 个冲突，等待手动处理');
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

    final totalActionCount = sortedActions.isEmpty ? 1 : sortedActions.length;
    if (sortedActions.isEmpty) {
      onProgress?.call(0.82, '没有需要传输的文件，正在确认同步记录');
    }
    for (var index = 0; index < sortedActions.length; index++) {
      final action = sortedActions[index];
      final progress = 0.28 + ((index + 1) / totalActionCount) * 0.54;
      onProgress?.call(
        progress,
        _labelForAction(action, current: index + 1, total: totalActionCount),
      );
      await _yieldToEventLoop();

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

    onProgress?.call(0.9, '刷新同步记录：保存本地和 OneDrive 最新状态');
    await _yieldToEventLoop();
    await _refreshSyncState(deletedRemotePaths: deletedRemotePaths);
    onProgress?.call(
      1,
      '同步完成：上传 ${uploadedPaths.length}，下载 ${downloadedPaths.length}，云端删除 ${deletedRemotePaths.length}，本地删除 ${deletedLocalPaths.length}',
    );

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

  String _labelForAction(
    SyncAction action, {
    required int current,
    required int total,
  }) {
    final path = _compactPath(action.relativePath);
    switch (action.type) {
      case SyncActionType.download:
        return '下载 $current/$total：$path';
      case SyncActionType.upload:
        return '上传 $current/$total：$path';
      case SyncActionType.deleteLocal:
        return '删除本地 $current/$total：$path';
      case SyncActionType.deleteRemote:
        return '删除云端 $current/$total：$path';
      case SyncActionType.conflict:
        return '冲突 $current/$total：$path';
    }
  }

  String _compactPath(String relativePath) {
    const maxLength = 58;
    if (relativePath.length <= maxLength) {
      return relativePath;
    }
    final segments = relativePath.split('/');
    if (segments.length >= 2) {
      final compact = '${segments.first}/.../${segments.last}';
      if (compact.length <= maxLength) {
        return compact;
      }
    }
    return '...${relativePath.substring(relativePath.length - maxLength + 3)}';
  }

  bool _isJsonPath(String relativePath) {
    return relativePath.endsWith('.json');
  }

  Future<void> _yieldToEventLoop() => Future<void>.delayed(Duration.zero);

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
    final refreshedRemoteSnapshot = await remoteSource.fetchSnapshot(
      baseline: await storage.loadSyncState(provider),
      onProgress: (remoteProgress, label) {
        final mappedProgress = 0.92 + remoteProgress.clamp(0, 1) * 0.06;
        onProgress?.call(mappedProgress, '刷新记录：$label');
      },
    );
    final refreshedRemoteFiles = refreshedRemoteSnapshot.files
        .where((file) => attachmentPolicy.includeRemotePath(file.relativePath))
        .toList();
    final refreshedState = SyncState(
      lastSyncedAt: DateTime.now(),
      lastKnownRemoteCursor: refreshedRemoteSnapshot.cursor,
      lastKnownRemoteRootId: refreshedRemoteSnapshot.remoteRootId,
      lastKnownLocalFingerprints: {
        for (final file in refreshedLocalFiles)
          file.relativePath: file.fingerprint,
      },
      lastKnownRemoteRevisions: {
        for (final file in refreshedRemoteFiles)
          file.relativePath: file.revision,
      },
      lastKnownRemoteNodes: refreshedRemoteSnapshot.remoteNodes,
    );
    await storage.saveSyncState(refreshedState, provider);
    if (deletedRemotePaths.isNotEmpty) {
      await storage.acknowledgeTombstones(deletedRemotePaths);
    }
  }
}
