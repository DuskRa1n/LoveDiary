import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/diary_storage.dart';
import '../ui/onedrive_connect_page.dart';
import '../utils/app_log.dart';
import '../utils/background_task.dart';
import 'diary_sync_executor.dart';
import 'onedrive/onedrive_app_config.dart';
import 'onedrive/onedrive_auth_service.dart';
import 'onedrive/onedrive_models.dart';
import 'onedrive/onedrive_remote_source.dart';
import 'sync_foreground_guard.dart';
import 'sync_models.dart';
import 'sync_remote_source.dart';

enum SyncRunStatus { success, failed, conflict, cancelled, skipped }

class SyncRunOutcome {
  const SyncRunOutcome._(this.status, {this.result, this.message});

  final SyncRunStatus status;
  final SyncExecutionResult? result;
  final String? message;

  bool get isSuccess => status == SyncRunStatus.success;

  factory SyncRunOutcome.success(SyncExecutionResult result) {
    return SyncRunOutcome._(SyncRunStatus.success, result: result);
  }

  factory SyncRunOutcome.failed(String message) {
    return SyncRunOutcome._(SyncRunStatus.failed, message: message);
  }

  factory SyncRunOutcome.conflict(SyncExecutionResult result) {
    return SyncRunOutcome._(SyncRunStatus.conflict, result: result);
  }

  factory SyncRunOutcome.cancelled(String message) {
    return SyncRunOutcome._(SyncRunStatus.cancelled, message: message);
  }

  static const skipped = SyncRunOutcome._(SyncRunStatus.skipped);
}

class SyncStatusEntry {
  const SyncStatusEntry({
    required this.label,
    required this.progress,
    required this.recordedAt,
  });

  final String label;
  final double progress;
  final DateTime recordedAt;
}

typedef ShowPageCallback = Future<T?> Function<T>(Route<T> page);
typedef ShowMessageCallback = void Function(String message);
typedef LoadAppDataCallback = Future<void> Function();
typedef ShowConfirmCallback =
    Future<bool> Function(String title, String content);
typedef ShowSyncResultDialogCallback =
    Future<void> Function({
      required String sourceLabel,
      required SyncExecutionResult result,
    });
typedef HandleSyncConflictsCallback =
    Future<void> Function({
      required List<String> conflictPaths,
      required List<SyncConflictDetail> conflictDetails,
      required DiarySyncRemoteSource remoteSource,
      required SyncProvider provider,
      required void Function(bool value) setSyncing,
    });
typedef OpenUsSheetCallback = Future<void> Function();

class SyncController extends ChangeNotifier {
  SyncController({required this.storage, required this.onShowMessage});

  final DiaryStorage storage;
  final ShowMessageCallback onShowMessage;

  static const _foregroundUpdateInterval = Duration(milliseconds: 350);

  final ValueNotifier<bool> _writeLockedListenable = ValueNotifier(false);
  final ValueNotifier<int> _syncStatusRevision = ValueNotifier(0);

  bool _isConnectingOneDrive = false;
  bool _isSyncingOneDrive = false;
  bool _isCancellingOneDriveSync = false;
  bool _hasCheckedStartupOneDriveSync = false;
  bool _startupRestoreRequested = false;
  DateTime? _lastSyncedAt;
  DateTime? _lastSyncFailedAt;
  String? _lastSyncFailureMessage;
  DateTime? _syncStartedAt;
  double? _oneDriveSyncProgress;
  String? _oneDriveSyncLabel;
  final List<SyncStatusEntry> _syncStatusHistory = [];
  DateTime? _lastForegroundUpdateAt;
  String? _syncCancellationReason;
  OneDriveSyncConfig? _oneDriveConfig;
  OneDriveAuthService? _cachedAuthService;
  OneDriveRemoteSource? _cachedRemoteSource;

  // ── public getters ──────────────────────────────────────────────────────

  bool get isWriteLocked => _writeLockedListenable.value;
  ValueNotifier<bool> get writeLockedListenable => _writeLockedListenable;
  ValueNotifier<int> get syncStatusRevision => _syncStatusRevision;

  bool get isConnectingOneDrive => _isConnectingOneDrive;
  bool get isSyncingOneDrive => _isSyncingOneDrive;
  bool get isCancellingOneDriveSync => _isCancellingOneDriveSync;
  bool get startupRestoreRequested => _startupRestoreRequested;

  OneDriveSyncConfig? get oneDriveConfig => _oneDriveConfig;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  DateTime? get lastSyncFailedAt => _lastSyncFailedAt;
  String? get lastSyncFailureMessage => _lastSyncFailureMessage;
  DateTime? get syncStartedAt => _syncStartedAt;
  double? get oneDriveSyncProgress => _oneDriveSyncProgress;
  String? get oneDriveSyncLabel => _oneDriveSyncLabel;

  // ── bridge helpers ──────────────────────────────────────────────────────

  bool applyLoadedState({
    required SyncState syncState,
    required OneDriveSyncConfig? config,
  }) {
    _lastSyncedAt = syncState.lastSyncedAt;
    _lastSyncFailedAt = syncState.lastFailedAt;
    _lastSyncFailureMessage = syncState.lastFailureMessage;
    _oneDriveConfig = config;
    notifyListeners();

    if (shouldRunStartupSync(syncState.lastSyncedAt)) {
      _hasCheckedStartupOneDriveSync = true;
      return true;
    }
    return false;
  }

  void resetSyncState() {
    _lastSyncedAt = null;
    _lastSyncFailedAt = null;
    _lastSyncFailureMessage = null;
    _oneDriveConfig = null;
  }

  // ── write lock ─────────────────────────────────────────────────────────

  void _setOneDriveSyncing(bool value) {
    _isSyncingOneDrive = value;
    _writeLockedListenable.value = value;
  }

  bool guardWritableAction() {
    if (!isWriteLocked) {
      return true;
    }
    showWriteLockedMessage();
    return false;
  }

  void showWriteLockedMessage() {
    onShowMessage('正在同步中，你可以继续查看；保存、评论、修改和删除稍后再操作。');
  }

  // ── service access ──────────────────────────────────────────────────────

  OneDriveAuthService _oneDriveAuthService() {
    _cachedAuthService ??= OneDriveAuthService(storage: storage);
    return _cachedAuthService!;
  }

  OneDriveRemoteSource _oneDriveRemoteSource() {
    _cachedRemoteSource ??= OneDriveRemoteSource(
      authService: _oneDriveAuthService(),
    );
    return _cachedRemoteSource!;
  }

  OneDriveAuthService exposeAuthService() => _oneDriveAuthService();

  void disconnectAuthService() {
    _cachedRemoteSource?.dispose();
    _cachedRemoteSource = null;
    _cachedAuthService?.dispose();
    _cachedAuthService = null;
  }

  // ── sync status tracking ───────────────────────────────────────────────

  void _recordSyncStatus(double progress, String label) {
    final normalizedProgress = progress.clamp(0, 1).toDouble();
    _oneDriveSyncProgress = normalizedProgress;
    _oneDriveSyncLabel = label;
    if (_syncStatusHistory.isEmpty ||
        _syncStatusHistory.last.label != label ||
        (_syncStatusHistory.last.progress - normalizedProgress).abs() > 0.001) {
      _syncStatusHistory.add(
        SyncStatusEntry(
          label: label,
          progress: normalizedProgress,
          recordedAt: DateTime.now(),
        ),
      );
      if (_syncStatusHistory.length > 80) {
        _syncStatusHistory.removeRange(0, _syncStatusHistory.length - 80);
      }
    }
    _syncStatusRevision.value += 1;
  }

  List<SyncStatusEntry> currentSyncStatusHistory() {
    final history = List<SyncStatusEntry>.from(_syncStatusHistory.reversed);
    final currentLabel = _oneDriveSyncLabel;
    if (history.isEmpty && currentLabel != null) {
      history.add(
        SyncStatusEntry(
          label: currentLabel,
          progress: _oneDriveSyncProgress ?? 0,
          recordedAt: DateTime.now(),
        ),
      );
    }
    return history;
  }

  Future<void> _updateForegroundSyncStatus({
    required String label,
    double? progress,
    bool force = false,
  }) async {
    final now = DateTime.now();
    final lastUpdateAt = _lastForegroundUpdateAt;
    if (!force &&
        progress != 1 &&
        lastUpdateAt != null &&
        now.difference(lastUpdateAt) < _foregroundUpdateInterval) {
      return;
    }
    _lastForegroundUpdateAt = now;
    await SyncForegroundGuard.update(label: label, progress: progress);
  }

  Future<void> _yieldToUi() => Future<void>.delayed(Duration.zero);

  void _checkSyncCancelled() {
    if (_isCancellingOneDriveSync) {
      throw SyncCancelledException(
        _syncCancellationReason ?? 'OneDrive 同步已取消。',
      );
    }
  }

  // ── cancel sync ─────────────────────────────────────────────────────────

  void cancelOneDriveSync() {
    if (!_isSyncingOneDrive || _isCancellingOneDriveSync) {
      return;
    }
    _isCancellingOneDriveSync = true;
    _syncCancellationReason = 'OneDrive 同步已取消。';
    _recordSyncStatus(_oneDriveSyncProgress ?? 0, '已请求取消：正在等待当前网络步骤安全结束');
    notifyListeners();
    unawaitedLogged(
      'Update foreground cancellation status failed',
      () => _updateForegroundSyncStatus(
        label: '正在取消 OneDrive 同步…',
        progress: _oneDriveSyncProgress,
        force: true,
      ),
    );
  }

  // ── connect OneDrive ────────────────────────────────────────────────────

  Future<void> connectOneDrive({
    required ShowPageCallback showPage,
    required LoadAppDataCallback loadAppData,
    OpenUsSheetCallback? openUsSheet,
  }) async {
    if (_isConnectingOneDrive || _isSyncingOneDrive) {
      if (_isSyncingOneDrive) {
        onShowMessage('同步中，OneDrive 连接操作稍后再进行。');
      }
      return;
    }

    _isConnectingOneDrive = true;
    notifyListeners();

    try {
      final config = await showPage<OneDriveSyncConfig>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => OneDriveConnectPage(
            authService: _oneDriveAuthService(),
            clientId: kOneDriveClientId,
            tenant: kOneDriveTenant,
            remoteFolder:
                _oneDriveConfig?.remoteFolder ?? kOneDriveRemoteFolder,
          ),
        ),
      );

      if (config == null) {
        return;
      }

      disconnectAuthService();
      _oneDriveConfig = config;
      notifyListeners();
      onShowMessage('OneDrive 已连接');
      if (_startupRestoreRequested) {
        unawaitedLogged(
          'Startup OneDrive restore after connect failed',
          () => restoreFromOneDriveAtStartup(loadAppData: loadAppData),
        );
      }
    } catch (error) {
      onShowMessage('连接 OneDrive 失败：$error');
    } finally {
      _isConnectingOneDrive = false;
      notifyListeners();
    }
  }

  // ── update config ───────────────────────────────────────────────────────

  Future<void> updateOneDriveConfig({
    required OneDriveSyncConfig updated,
    required bool resetSyncBaseline,
  }) async {
    if (resetSyncBaseline) {
      await storage.resetSyncState(SyncProvider.oneDrive);
    }
    await storage.saveOneDriveSyncConfig(updated);
    disconnectAuthService();
    _oneDriveConfig = updated;
    if (resetSyncBaseline) {
      _lastSyncedAt = null;
      _lastSyncFailedAt = null;
      _lastSyncFailureMessage = null;
    }
    notifyListeners();
  }

  // ── sync with OneDrive ──────────────────────────────────────────────────

  Future<SyncRunOutcome> syncWithOneDrive({
    bool interactive = true,
    required LoadAppDataCallback loadAppData,
    ShowSyncResultDialogCallback? showResultDialog,
    HandleSyncConflictsCallback? handleSyncConflicts,
  }) async {
    if (_oneDriveConfig == null ||
        _isConnectingOneDrive ||
        _isSyncingOneDrive) {
      return SyncRunOutcome.skipped;
    }

    const initialSyncLabel = '准备同步：连接 OneDrive';
    _setOneDriveSyncing(true);
    _isCancellingOneDriveSync = false;
    _syncCancellationReason = null;
    _syncStartedAt = DateTime.now();
    _syncStatusHistory.clear();
    _recordSyncStatus(0, initialSyncLabel);
    _lastForegroundUpdateAt = null;
    notifyListeners();

    try {
      await _yieldToUi();
      await SyncForegroundGuard.start(label: initialSyncLabel, progress: 0);
      _lastForegroundUpdateAt = DateTime.now();
      await _yieldToUi();

      final remoteSource = _oneDriveRemoteSource();
      final executor = DiarySyncExecutor(
        storage: storage,
        remoteSource: remoteSource,
        provider: SyncProvider.oneDrive,
        safetyPolicy: SyncSafetyPolicy(
          maxDestructiveActions: _oneDriveConfig!.maxDestructiveActions,
        ),
        attachmentPolicy: const AttachmentSyncPolicy(),
        onProgress: (progress, label) {
          unawaitedLogged(
            'Update foreground sync progress failed',
            () => _updateForegroundSyncStatus(label: label, progress: progress),
          );
          _recordSyncStatus(progress, label);
        },
        checkCancelled: _checkSyncCancelled,
      );
      final result = await executor.sync();
      await loadAppData();

      if (result.hasConflicts) {
        if (!interactive) {
          onShowMessage('自动同步发现冲突，请手动同步后处理。');
          return SyncRunOutcome.conflict(result);
        }
        if (handleSyncConflicts != null) {
          await handleSyncConflicts(
            conflictPaths: result.conflictPaths,
            conflictDetails: result.conflictDetails,
            remoteSource: remoteSource,
            provider: SyncProvider.oneDrive,
            setSyncing: (value) {
              _setOneDriveSyncing(value);
              notifyListeners();
            },
          );
        }
        return SyncRunOutcome.conflict(result);
      }

      if (interactive && showResultDialog != null) {
        await showResultDialog(sourceLabel: 'OneDrive', result: result);
      }
      return SyncRunOutcome.success(result);
    } on SyncSafetyException catch (error) {
      await recordSyncFailure(SyncProvider.oneDrive, error.message);
      onShowMessage(error.message);
      return SyncRunOutcome.failed(error.message);
    } on OneDriveAuthException catch (error) {
      await recordSyncFailure(SyncProvider.oneDrive, error.message);
      onShowMessage(error.message);
      return SyncRunOutcome.failed(error.message);
    } on SyncCancelledException catch (error) {
      final message = error.message;
      onShowMessage(message);
      return SyncRunOutcome.cancelled(message);
    } catch (error) {
      final message = 'OneDrive 同步失败：$error';
      await recordSyncFailure(SyncProvider.oneDrive, message);
      onShowMessage(message);
      return SyncRunOutcome.failed(message);
    } finally {
      await SyncForegroundGuard.stop();
      _setOneDriveSyncing(false);
      _isCancellingOneDriveSync = false;
      _syncCancellationReason = null;
      _oneDriveSyncProgress = null;
      _oneDriveSyncLabel = null;
      _syncStartedAt = null;
      _lastForegroundUpdateAt = null;
      _syncStatusRevision.value += 1;
      notifyListeners();
    }
  }

  // ── disconnect OneDrive ─────────────────────────────────────────────────

  Future<bool> disconnectOneDrive({
    required ShowConfirmCallback showConfirm,
  }) async {
    if (_oneDriveConfig == null ||
        _isConnectingOneDrive ||
        _isSyncingOneDrive) {
      if (_isSyncingOneDrive) {
        onShowMessage('同步中，断开连接稍后再操作。');
      }
      return false;
    }

    final confirmed = await showConfirm(
      '断开 OneDrive',
      '这只会移除当前设备上的 OneDrive 登录状态，不会删除本地数据或云端文件。',
    );

    if (!confirmed) {
      return false;
    }

    final authService = _oneDriveAuthService();
    await authService.disconnect();
    disconnectAuthService();
    _oneDriveConfig = null;
    _lastSyncedAt = null;
    _lastSyncFailedAt = null;
    _lastSyncFailureMessage = null;
    notifyListeners();
    onShowMessage('已断开 OneDrive');
    return true;
  }

  // ── auto sync ───────────────────────────────────────────────────────────

  Future<void> triggerAutoSync({
    required String reason,
    required LoadAppDataCallback loadAppData,
    ShowSyncResultDialogCallback? showResultDialog,
    HandleSyncConflictsCallback? handleSyncConflicts,
  }) async {
    if (_isConnectingOneDrive || _isSyncingOneDrive) {
      return;
    }

    final config = _oneDriveConfig;
    if (config == null) {
      return;
    }

    if (config.syncOnWrite == false) {
      return;
    }

    if (config.minimumSyncIntervalMinutes > 0 && _lastSyncedAt != null) {
      final minimumInterval = Duration(
        minutes: config.minimumSyncIntervalMinutes,
      );
      if (DateTime.now().difference(_lastSyncedAt!) < minimumInterval) {
        return;
      }
    }

    final outcome = await syncWithOneDrive(
      interactive: false,
      loadAppData: loadAppData,
      showResultDialog: showResultDialog,
      handleSyncConflicts: handleSyncConflicts,
    );
    if (outcome.isSuccess) {
      onShowMessage('已经把小日子放到云端了');
    }
  }

  // ── record sync failure ─────────────────────────────────────────────────

  Future<void> recordSyncFailure(SyncProvider provider, String message) async {
    final currentState = await storage.loadSyncState(provider);
    final failedState = currentState.copyWith(
      lastFailedAt: DateTime.now(),
      lastFailureMessage: message,
    );
    await storage.saveSyncState(failedState, provider);
    if (provider == SyncProvider.oneDrive) {
      _lastSyncFailedAt = failedState.lastFailedAt;
      _lastSyncFailureMessage = failedState.lastFailureMessage;
      notifyListeners();
    }
  }

  // ── startup OneDrive restore ────────────────────────────────────────────

  Future<void> startStartupOneDriveRestore({
    required ShowMessageCallback showMessage,
    required OpenUsSheetCallback openUsSheet,
    required LoadAppDataCallback loadAppData,
  }) async {
    if (_startupRestoreRequested) {
      return;
    }

    _startupRestoreRequested = true;
    notifyListeners();
    if (_oneDriveConfig == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openUsSheet();
        showMessage('已进入主页面。请手动连接 OneDrive，连接完成后会自动开始恢复。');
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaitedLogged(
        'Startup OneDrive restore failed',
        () => restoreFromOneDriveAtStartup(loadAppData: loadAppData),
      );
    });
  }

  Future<void> restoreFromOneDriveAtStartup({
    required LoadAppDataCallback loadAppData,
  }) async {
    if (_oneDriveConfig == null || _isSyncingOneDrive) {
      return;
    }

    const initialRestoreLabel = '准备恢复：读取 OneDrive 数据';
    _setOneDriveSyncing(true);
    _syncStartedAt = DateTime.now();
    _syncStatusHistory.clear();
    _recordSyncStatus(0, initialRestoreLabel);
    _lastForegroundUpdateAt = null;
    notifyListeners();

    try {
      await _yieldToUi();
      await SyncForegroundGuard.start(label: initialRestoreLabel, progress: 0);
      _lastForegroundUpdateAt = DateTime.now();
      await _yieldToUi();
      final remoteSource = _oneDriveRemoteSource();
      final snapshot = await remoteSource.fetchSnapshot(
        baseline: await storage.loadSyncState(SyncProvider.oneDrive),
        onProgress: (remoteProgress, label) {
          final mappedProgress = 0.05 + remoteProgress.clamp(0, 1) * 0.25;
          unawaitedLogged(
            'Update foreground restore progress failed',
            () => _updateForegroundSyncStatus(
              label: label,
              progress: mappedProgress,
            ),
          );
          _recordSyncStatus(mappedProgress, label);
        },
        checkCancelled: _checkSyncCancelled,
      );
      const attachmentPolicy = AttachmentSyncPolicy();
      final filesToRestore = snapshot.files
          .where(
            (file) => attachmentPolicy.includeRemotePath(file.relativePath),
          )
          .toList();
      if (filesToRestore.isEmpty) {
        onShowMessage('OneDrive 里还没有可恢复的数据。');
        return;
      }

      final rootDirectory = await storage.resolveRootDirectory();
      final restoreStamp = DateTime.now().microsecondsSinceEpoch.toString();
      final stagingDirectory = Directory(
        p.join(
          rootDirectory.path,
          'sync',
          'startup_restore_staging_$restoreStamp',
        ),
      );
      final backupDirectory = Directory(
        p.join(
          rootDirectory.path,
          'sync',
          'startup_restore_backup_$restoreStamp',
        ),
      );
      var committedRestore = false;
      try {
        for (var index = 0; index < filesToRestore.length; index++) {
          _checkSyncCancelled();
          final file = filesToRestore[index];
          final progress = 0.35 + ((index + 1) / filesToRestore.length) * 0.45;
          final label =
              '恢复下载 ${index + 1}/${filesToRestore.length}：${file.relativePath}';
          unawaitedLogged(
            'Update foreground restore download progress failed',
            () => _updateForegroundSyncStatus(label: label, progress: progress),
          );
          _recordSyncStatus(progress, label);
          final stagedAbsolutePath = _stagedRestorePath(
            stagingDirectory,
            file.relativePath,
          );
          final stagedFile = File(stagedAbsolutePath);
          await stagedFile.parent.create(recursive: true);
          await remoteSource.downloadFile(
            relativePath: file.relativePath,
            targetAbsolutePath: stagedAbsolutePath,
            isBinary: file.isBinary,
            checkCancelled: _checkSyncCancelled,
          );
          if (!await stagedFile.exists()) {
            throw StateError('恢复下载缺少文件：${file.relativePath}');
          }
        }
        _checkSyncCancelled();
        await _commitStagedRestoreFiles(
          stagingDirectory: stagingDirectory,
          backupDirectory: backupDirectory,
          filesToRestore: filesToRestore,
        );
        committedRestore = true;
      } finally {
        await _deleteDirectoryQuietly(stagingDirectory);
        if (committedRestore) {
          await _deleteDirectoryQuietly(backupDirectory);
        }
      }

      final localFiles = (await storage.listSyncFiles())
          .where((file) => attachmentPolicy.includeLocalPath(file.relativePath))
          .toList();
      await storage.saveSyncState(
        SyncState(
          lastSyncedAt: DateTime.now(),
          lastKnownRemoteCursor: snapshot.cursor,
          lastKnownRemoteRootId: snapshot.remoteRootId,
          lastKnownLocalFingerprints: {
            for (final file in localFiles) file.relativePath: file.fingerprint,
          },
          lastKnownRemoteRevisions: {
            for (final file in filesToRestore) file.relativePath: file.revision,
          },
          lastKnownRemoteNodes: snapshot.remoteNodes,
          lastFailedAt: null,
          lastFailureMessage: null,
        ),
        SyncProvider.oneDrive,
      );
      await loadAppData();

      _recordSyncStatus(1, '恢复完成：已从 OneDrive 下载 ${filesToRestore.length} 个文件');
      onShowMessage('已从 OneDrive 恢复本地数据。');
    } on SyncCancelledException catch (error) {
      onShowMessage(error.message);
    } on OneDriveAuthException catch (error) {
      onShowMessage(error.message);
    } catch (error) {
      onShowMessage('恢复失败：$error');
    } finally {
      await SyncForegroundGuard.stop();
      _setOneDriveSyncing(false);
      _oneDriveSyncProgress = null;
      _oneDriveSyncLabel = null;
      _syncStartedAt = null;
      _lastForegroundUpdateAt = null;
      _syncStatusRevision.value += 1;
      notifyListeners();
    }
  }

  // ── startup sync decision ───────────────────────────────────────────────

  String _stagedRestorePath(Directory directory, String relativePath) {
    final normalized = SyncFilePolicy.normalizeSyncableBusinessPath(
      relativePath,
    );
    return p.joinAll([directory.path, ...normalized.split('/')]);
  }

  Future<void> _commitStagedRestoreFiles({
    required Directory stagingDirectory,
    required Directory backupDirectory,
    required List<RemoteSyncFile> filesToRestore,
  }) async {
    final backedUpPaths = <String>[];
    final createdPaths = <String>[];
    try {
      for (final file in filesToRestore) {
        _checkSyncCancelled();
        final targetAbsolutePath = await storage.resolveSyncFileAbsolutePath(
          file.relativePath,
        );
        final targetFile = File(targetAbsolutePath);
        final stagedFile = File(
          _stagedRestorePath(stagingDirectory, file.relativePath),
        );
        if (!await stagedFile.exists()) {
          throw StateError('恢复合并缺少暂存文件：${file.relativePath}');
        }

        final targetExisted = await targetFile.exists();
        if (targetExisted) {
          final backupFile = File(
            _stagedRestorePath(backupDirectory, file.relativePath),
          );
          await backupFile.parent.create(recursive: true);
          await targetFile.copy(backupFile.path);
          backedUpPaths.add(file.relativePath);
        } else {
          createdPaths.add(file.relativePath);
        }

        await targetFile.parent.create(recursive: true);
        await stagedFile.copy(targetFile.path);
      }
    } catch (error, stackTrace) {
      AppLog.error('提交 OneDrive 恢复暂存文件失败', error, stackTrace);
      await _rollbackStagedRestore(
        backupDirectory: backupDirectory,
        backedUpPaths: backedUpPaths,
        createdPaths: createdPaths,
      );
      rethrow;
    }
  }

  Future<void> _rollbackStagedRestore({
    required Directory backupDirectory,
    required List<String> backedUpPaths,
    required List<String> createdPaths,
  }) async {
    for (final relativePath in createdPaths.reversed) {
      try {
        final targetFile = File(
          await storage.resolveSyncFileAbsolutePath(relativePath),
        );
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } catch (error, stackTrace) {
        AppLog.warn('回滚 OneDrive 恢复新增文件失败：$relativePath');
        AppLog.error(
          'OneDrive restore rollback create cleanup failed',
          error,
          stackTrace,
        );
      }
    }

    for (final relativePath in backedUpPaths.reversed) {
      try {
        final backupFile = File(
          _stagedRestorePath(backupDirectory, relativePath),
        );
        final targetFile = File(
          await storage.resolveSyncFileAbsolutePath(relativePath),
        );
        if (await backupFile.exists()) {
          await targetFile.parent.create(recursive: true);
          await backupFile.copy(targetFile.path);
        }
      } catch (error, stackTrace) {
        AppLog.warn('回滚 OneDrive 恢复备份文件失败：$relativePath');
        AppLog.error(
          'OneDrive restore rollback backup copy failed',
          error,
          stackTrace,
        );
      }
    }
  }

  Future<void> _deleteDirectoryQuietly(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      AppLog.warn('清理临时目录失败：${directory.path}');
      AppLog.error('Temporary directory cleanup failed', error, stackTrace);
    }
  }

  bool shouldRunStartupSync(DateTime? lastSyncedAt) {
    if (_hasCheckedStartupOneDriveSync) {
      return false;
    }
    if (_oneDriveConfig == null || _startupRestoreRequested) {
      return false;
    }
    if (lastSyncedAt == null) {
      return true;
    }
    final syncPoint = _latestReachedStartupSyncPoint(DateTime.now());
    return lastSyncedAt.isBefore(syncPoint);
  }

  DateTime _latestReachedStartupSyncPoint(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    const checkpointHours = [6, 12, 18];

    for (final hour in checkpointHours.reversed) {
      final checkpoint = today.add(Duration(hours: hour));
      if (!now.isBefore(checkpoint)) {
        return checkpoint;
      }
    }

    return today
        .subtract(const Duration(days: 1))
        .add(const Duration(hours: 18));
  }

  // ── lifecycle ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cachedRemoteSource?.dispose();
    _cachedAuthService?.dispose();
    _writeLockedListenable.dispose();
    _syncStatusRevision.dispose();
    super.dispose();
  }
}
