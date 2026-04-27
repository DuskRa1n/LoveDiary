import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'data/diary_storage.dart';
import 'models/diary_models.dart';
import 'sync/diary_sync_executor.dart';
import 'sync/onedrive/onedrive_app_config.dart';
import 'sync/onedrive/onedrive_auth_service.dart';
import 'sync/onedrive/onedrive_models.dart';
import 'sync/onedrive/onedrive_remote_source.dart';
import 'sync/sync_models.dart';
import 'sync/sync_remote_source.dart';
import 'sync/sync_foreground_guard.dart';
import 'ui/diary_design.dart';
import 'ui/daily_quotes.dart';
import 'ui/onedrive_connect_page.dart';
import 'ui/real_today_tab.dart';
import 'ui/real_timeline_tab.dart';
import 'ui/real_us_tab.dart';
import 'ui/sync_messages.dart';
import 'ui/sync_conflict_page.dart';

const List<String> kDiaryMoods = ['开心', '安心', '温柔', '想念', '真诚', '治愈', '甜'];

class LoveDailyApp extends StatelessWidget {
  const LoveDailyApp({super.key, this.storage = const DiaryStorage()});

  final DiaryStorage storage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '恋爱日记',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: DiaryPalette.paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: DiaryPalette.rose,
          brightness: Brightness.light,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: DiaryPalette.ink,
          displayColor: DiaryPalette.ink,
        ),
        cardTheme: CardThemeData(
          color: DiaryPalette.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        dividerColor: DiaryPalette.line,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: DiaryPalette.ink,
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: DiaryPalette.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: DiaryPalette.white.withValues(alpha: 0.82),
          indicatorColor: DiaryPalette.mist,
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: selected ? DiaryPalette.rose : DiaryPalette.wine,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? DiaryPalette.rose : DiaryPalette.wine,
            );
          }),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: DiaryPalette.rose,
          foregroundColor: Colors.white,
          extendedTextStyle: TextStyle(fontWeight: FontWeight.w800),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: DiaryPalette.rose,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: DiaryPalette.wine,
            side: const BorderSide(color: DiaryPalette.line),
            backgroundColor: DiaryPalette.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: DiaryPalette.white.withValues(alpha: 0.86),
          hintStyle: const TextStyle(color: DiaryPalette.wine),
          prefixIconColor: DiaryPalette.wine,
          suffixIconColor: DiaryPalette.wine,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: DiaryPalette.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: DiaryPalette.rose, width: 1.2),
          ),
        ),
      ),
      home: LoveDailyShell(storage: storage),
    );
  }
}

class LoveDailyShell extends StatefulWidget {
  const LoveDailyShell({super.key, this.storage = const DiaryStorage()});

  final DiaryStorage storage;

  @override
  State<LoveDailyShell> createState() => _LoveDailyShellState();
}

enum SyncRunStatus { success, failed, conflict, skipped }

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

  static const skipped = SyncRunOutcome._(SyncRunStatus.skipped);
}

class _SyncStatusEntry {
  const _SyncStatusEntry({
    required this.label,
    required this.progress,
    required this.recordedAt,
  });

  final String label;
  final double progress;
  final DateTime recordedAt;
}

class _LoveDailyShellState extends State<LoveDailyShell> {
  static const Duration _syncExecutionTimeout = Duration(minutes: 12);
  static const Duration _foregroundUpdateInterval = Duration(milliseconds: 600);

  late final String _startupQuote = randomDailyQuote();
  final ValueNotifier<bool> _writeLockedListenable = ValueNotifier(false);
  final ValueNotifier<int> _syncStatusRevision = ValueNotifier(0);
  final PageController _pageController = PageController();
  List<DiaryEntry> _entries = const [];
  CoupleProfile _profile = DiaryStorage.seedProfile();
  bool _isLoaded = false;
  bool _isConnectingOneDrive = false;
  bool _isSyncingOneDrive = false;
  bool _hasCheckedStartupOneDriveSync = false;
  bool _startupRestoreRequested = false;
  int _currentIndex = 0;
  DateTime? _lastSyncedAt;
  DateTime? _lastSyncFailedAt;
  String? _lastSyncFailureMessage;
  DateTime? _syncStartedAt;
  double? _oneDriveSyncProgress;
  String? _oneDriveSyncLabel;
  final List<_SyncStatusEntry> _syncStatusHistory = [];
  String _syncWaitingMessage = randomSyncWaitingMessage();
  DateTime? _lastForegroundUpdateAt;
  OneDriveSyncConfig? _oneDriveConfig;
  String? _storageRootPath;
  String? _startupLoadError;

  @override
  void initState() {
    super.initState();
    _loadAppData();
  }

  @override
  void dispose() {
    _writeLockedListenable.dispose();
    _syncStatusRevision.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool get _isWriteLocked => _writeLockedListenable.value;

  void _setOneDriveSyncing(bool value) {
    _isSyncingOneDrive = value;
    _writeLockedListenable.value = value;
  }

  bool _guardWritableAction() {
    if (!_isWriteLocked) {
      return true;
    }
    _showWriteLockedMessage();
    return false;
  }

  void _showWriteLockedMessage() {
    _showMessage('正在同步中，你可以继续查看；保存、评论、修改和删除稍后再操作。');
  }

  void _recordSyncStatus(double progress, String label) {
    _oneDriveSyncProgress = progress;
    _oneDriveSyncLabel = label;
    if (_syncStatusHistory.isEmpty ||
        _syncStatusHistory.last.label != label ||
        _syncStatusHistory.last.progress != progress) {
      _syncStatusHistory.add(
        _SyncStatusEntry(
          label: label,
          progress: progress,
          recordedAt: DateTime.now(),
        ),
      );
      if (_syncStatusHistory.length > 24) {
        _syncStatusHistory.removeAt(0);
      }
    }
    _syncStatusRevision.value += 1;
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

  void _selectTab(int index, {bool animate = true}) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }

    void movePage() {
      if (!_pageController.hasClients) {
        return;
      }
      if (animate) {
        unawaited(
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
          ),
        );
        return;
      }
      _pageController.jumpToPage(index);
    }

    if (_pageController.hasClients) {
      movePage();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        movePage();
      }
    });
  }

  Future<void> _loadAppData() async {
    var currentStep = 'loadEntries';
    String? resolvedRootPath;
    try {
      final entries = await widget.storage.loadEntries();
      currentStep = 'loadProfile';
      final profile = await widget.storage.loadProfile();
      currentStep = 'resolveRootDirectory';
      final rootDirectory = await widget.storage.resolveRootDirectory();
      resolvedRootPath = rootDirectory.path;
      currentStep = 'loadSyncState';
      final syncState = await widget.storage.loadSyncState(
        SyncProvider.oneDrive,
      );
      currentStep = 'loadOneDriveSyncConfig';
      final oneDriveConfig = await widget.storage.loadOneDriveSyncConfig();

      if (!mounted) {
        return;
      }

      setState(() {
        _entries = entries;
        _profile = profile;
        _lastSyncedAt = syncState.lastSyncedAt;
        _lastSyncFailedAt = syncState.lastFailedAt;
        _lastSyncFailureMessage = syncState.lastFailureMessage;
        _oneDriveConfig = oneDriveConfig;
        _storageRootPath = rootDirectory.path;
        _startupLoadError = null;
        _isLoaded = true;
      });

      if (!_hasCheckedStartupOneDriveSync &&
          oneDriveConfig != null &&
          !_startupRestoreRequested &&
          _shouldRunStartupOneDriveSync(syncState.lastSyncedAt)) {
        _hasCheckedStartupOneDriveSync = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_syncWithOneDrive(interactive: false));
          }
        });
      }
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }

      final diagnostic = _buildStartupDiagnostic(
        currentStep: currentStep,
        storageRootPath: resolvedRootPath,
        error: error,
        stackTrace: stackTrace,
      );

      setState(() {
        _entries = const [];
        _profile = DiaryStorage.seedProfile();
        _lastSyncedAt = null;
        _lastSyncFailedAt = null;
        _lastSyncFailureMessage = null;
        _oneDriveConfig = null;
        _storageRootPath = resolvedRootPath;
        _startupLoadError = diagnostic;
        _isLoaded = true;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showMessage('启动时有一部分本地数据读取失败，已用安全模式继续进入。');
        }
      });
    }
  }

  Future<void> _retryLoadAppData() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoaded = false;
      _startupLoadError = null;
    });
    await _loadAppData();
  }

  String _buildStartupDiagnostic({
    required String currentStep,
    required Object error,
    required StackTrace stackTrace,
    String? storageRootPath,
  }) {
    final buffer = StringBuffer()
      ..writeln('阶段: $currentStep')
      ..writeln('模式: ${kDebugMode ? 'debug' : 'release'}')
      ..writeln('平台: ${Platform.operatingSystem}')
      ..writeln('时间: ${DateTime.now().toIso8601String()}');

    if (storageRootPath != null) {
      buffer.writeln('本地目录: $storageRootPath');
    }

    buffer
      ..writeln('异常: $error')
      ..writeln('堆栈:')
      ..write(stackTrace.toString());

    return buffer.toString();
  }

  Future<void> _showStartupDiagnostic() async {
    final diagnostic = _startupLoadError;
    if (diagnostic == null || !mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('启动诊断'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(
                diagnostic,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: diagnostic));
                if (context.mounted && mounted) {
                  Navigator.of(context).pop();
                  _showMessage('诊断内容已复制');
                }
              },
              child: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStartupErrorBanner() {
    if (_startupLoadError == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DiaryPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '启动时跳过了一部分异常数据',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: DiaryPalette.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '应用已经继续打开。你可以先正常使用，必要时再重新同步或重试读取。',
              style: TextStyle(color: DiaryPalette.wine, height: 1.45),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: _retryLoadAppData,
                    child: const Text('重新读取'),
                  ),
                  OutlinedButton(
                    onPressed: _showStartupDiagnostic,
                    child: const Text('查看诊断'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldOfferStartupRecovery({
    required List<DiaryEntry> entries,
    required CoupleProfile profile,
  }) {
    final hasLocalData = entries.isNotEmpty || profile.isOnboarded;
    return !hasLocalData;
  }

  bool _shouldRunStartupOneDriveSync(DateTime? lastSyncedAt) {
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

  Future<void> _persistProfile() => widget.storage.saveProfile(_profile);

  Future<void> _reloadEntries() async {
    final entries = await widget.storage.loadEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
    });
  }

  Future<DiaryEntry?> _openEditor({DiaryEntry? initialEntry}) async {
    if (!_guardWritableAction()) {
      return null;
    }

    final entry = await Navigator.of(context).push<DiaryEntry>(
      MaterialPageRoute(
        builder: (_) => CreateEntryPage(
          storage: widget.storage,
          profile: _profile,
          initialEntry: initialEntry,
          rootDirectoryPath: _storageRootPath,
          writeLockedListenable: _writeLockedListenable,
          onWriteBlocked: _showWriteLockedMessage,
        ),
      ),
    );

    if (entry == null) {
      return null;
    }

    final savedEntry = await widget.storage.saveEntry(entry);
    if (initialEntry == null) {
      await widget.storage.clearEntryDraft();
    }
    await _reloadEntries();

    if (!mounted) {
      return savedEntry;
    }

    _selectTab(1);

    if (!mounted) {
      return savedEntry;
    }

    final message = initialEntry == null ? '日记已保存到本地' : '日记已更新';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    unawaited(_triggerAutoSync(reason: initialEntry == null ? '发布日记' : '更新日记'));
    return savedEntry;
  }

  Future<DiaryEntry> _addComment(String entryId, DiaryComment comment) async {
    if (!_guardWritableAction()) {
      throw StateError('Write operations are disabled while syncing.');
    }

    final index = _entries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) {
      throw StateError('找不到对应的日记');
    }

    late DiaryEntry updatedEntry;
    setState(() {
      updatedEntry = _entries[index].copyWith(
        comments: [..._entries[index].comments, comment],
        updatedAt: DateTime.now(),
      );
      _entries[index] = updatedEntry;
    });
    await widget.storage.saveEntry(updatedEntry);
    await _reloadEntries();
    unawaited(_triggerAutoSync(reason: '发表评论'));
    return updatedEntry;
  }

  Future<DiaryEntry?> _editEntry(DiaryEntry entry) {
    return _openEditor(initialEntry: entry);
  }

  Future<void> _deleteEntry(DiaryEntry entry) async {
    if (!_guardWritableAction()) {
      return;
    }

    await widget.storage.deleteEntry(entry);
    await _reloadEntries();
    unawaited(_triggerAutoSync(reason: '删除日记'));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除《${entry.title}》')));
  }

  Future<void> _openProfileEditor({required bool firstSetup}) async {
    if (!firstSetup && !_guardWritableAction()) {
      return;
    }

    final updatedProfile = await Navigator.of(context).push<CoupleProfile>(
      MaterialPageRoute(
        fullscreenDialog: !firstSetup,
        builder: (_) => ProfileSetupPage(
          initialProfile: _profile,
          isFirstSetup: firstSetup,
          writeLockedListenable: firstSetup ? null : _writeLockedListenable,
          onWriteBlocked: firstSetup ? null : _showWriteLockedMessage,
        ),
      ),
    );

    if (updatedProfile == null) {
      return;
    }

    setState(() {
      _profile = updatedProfile;
    });
    await _persistProfile();
  }

  Future<void> _openDustbin() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DustbinPage(
          storage: widget.storage,
          writeLockedListenable: _writeLockedListenable,
          onWriteBlocked: _showWriteLockedMessage,
        ),
      ),
    );

    if (changed == true) {
      await _reloadEntries();
    }
  }

  void _openEntryDetail(DiaryEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntryDetailPage(
          profile: _profile,
          entry: entry,
          rootDirectoryPath: _storageRootPath,
          writeLockedListenable: _writeLockedListenable,
          onWriteBlocked: _showWriteLockedMessage,
          onAddComment: _addComment,
          onEditEntry: _editEntry,
          onDeleteEntry: _deleteEntry,
        ),
      ),
    );
  }

  OneDriveAuthService _oneDriveAuthService() {
    return OneDriveAuthService(storage: widget.storage);
  }

  OneDriveRemoteSource _oneDriveRemoteSource() {
    return OneDriveRemoteSource(authService: _oneDriveAuthService());
  }

  Future<void> _connectOneDrive({String? remoteFolder}) async {
    if (_isConnectingOneDrive || _isSyncingOneDrive) {
      if (_isSyncingOneDrive) {
        _showMessage('同步中，OneDrive 连接操作稍后再进行。');
      }
      return;
    }

    setState(() {
      _isConnectingOneDrive = true;
    });

    try {
      final config = await Navigator.of(context).push<OneDriveSyncConfig>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => OneDriveConnectPage(
            authService: _oneDriveAuthService(),
            clientId: kOneDriveClientId,
            tenant: kOneDriveTenant,
            remoteFolder:
                remoteFolder ??
                _oneDriveConfig?.remoteFolder ??
                kOneDriveRemoteFolder,
          ),
        ),
      );

      if (config == null || !mounted) {
        return;
      }

      setState(() {
        _oneDriveConfig = config;
      });
      _showMessage('OneDrive 已连接');
      if (_startupRestoreRequested) {
        unawaited(_restoreFromOneDriveAtStartup());
      }
    } catch (error) {
      if (mounted) {
        _showMessage('连接 OneDrive 失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingOneDrive = false;
        });
      }
    }
  }

  Future<void> _openOneDriveSettings() async {
    if (_isConnectingOneDrive || _isSyncingOneDrive) {
      if (_isSyncingOneDrive) {
        _showMessage('同步中，OneDrive 设置稍后再修改。');
      }
      return;
    }

    final defaults = _OneDriveConfigFormData(
      remoteFolder: _oneDriveConfig?.remoteFolder ?? kOneDriveRemoteFolder,
      syncOnWrite: _oneDriveConfig?.syncOnWrite ?? false,
      minimumSyncIntervalMinutes:
          _oneDriveConfig?.minimumSyncIntervalMinutes ?? 0,
      maxDestructiveActions: _oneDriveConfig?.maxDestructiveActions ?? 3,
      syncOriginals: _oneDriveConfig?.syncOriginals ?? false,
      downloadOriginals: _oneDriveConfig?.downloadOriginals ?? false,
      localOriginalRetentionDays:
          _oneDriveConfig?.localOriginalRetentionDays ?? 30,
    );
    final formData = await _showOneDriveConfigPage(defaults);
    if (formData == null) {
      return;
    }

    if (_oneDriveConfig == null) {
      await _connectOneDrive(remoteFolder: formData.remoteFolder);
      return;
    }

    final updated = _oneDriveConfig!.copyWith(
      remoteFolder: formData.remoteFolder,
      syncOnWrite: formData.syncOnWrite,
      minimumSyncIntervalMinutes: formData.minimumSyncIntervalMinutes,
      maxDestructiveActions: formData.maxDestructiveActions,
      syncOriginals: formData.syncOriginals,
      downloadOriginals: formData.downloadOriginals,
      localOriginalRetentionDays: formData.localOriginalRetentionDays,
    );
    final resetSyncBaseline =
        _oneDriveConfig!.remoteFolder != updated.remoteFolder;
    if (resetSyncBaseline) {
      await widget.storage.resetSyncState(SyncProvider.oneDrive);
    }
    await widget.storage.saveOneDriveSyncConfig(updated);
    if (!mounted) {
      return;
    }

    setState(() {
      _oneDriveConfig = updated;
      if (resetSyncBaseline) {
        _lastSyncedAt = null;
        _lastSyncFailedAt = null;
        _lastSyncFailureMessage = null;
      }
    });
    _showMessage('OneDrive 远端目录已更新');
  }

  Future<SyncRunOutcome> _syncWithOneDrive({bool interactive = true}) async {
    if (_oneDriveConfig == null ||
        _isConnectingOneDrive ||
        _isSyncingOneDrive) {
      return SyncRunOutcome.skipped;
    }

    const initialSyncLabel = '准备同步：连接 OneDrive';
    setState(() {
      _setOneDriveSyncing(true);
      _syncStartedAt = DateTime.now();
      _syncStatusHistory.clear();
      _recordSyncStatus(0, initialSyncLabel);
      _syncWaitingMessage = randomSyncWaitingMessage();
      _lastForegroundUpdateAt = null;
    });

    try {
      await _yieldToUi();
      await SyncForegroundGuard.start(label: initialSyncLabel, progress: 0);
      _lastForegroundUpdateAt = DateTime.now();
      await _yieldToUi();

      final remoteSource = _oneDriveRemoteSource();
      final executor = DiarySyncExecutor(
        storage: widget.storage,
        remoteSource: remoteSource,
        provider: SyncProvider.oneDrive,
        safetyPolicy: SyncSafetyPolicy(
          maxDestructiveActions: _oneDriveConfig!.maxDestructiveActions,
        ),
        attachmentPolicy: AttachmentSyncPolicy(
          syncOriginals: _oneDriveConfig!.syncOriginals,
          downloadOriginals: _oneDriveConfig!.downloadOriginals,
        ),
        onProgress: (progress, label) {
          unawaited(
            _updateForegroundSyncStatus(label: label, progress: progress),
          );
          if (!mounted) {
            return;
          }
          _recordSyncStatus(progress, label);
        },
      );
      final result = await executor.sync().timeout(_syncExecutionTimeout);
      await _loadAppData();

      if (!mounted) {
        return SyncRunOutcome.success(result);
      }

      if (result.hasConflicts) {
        if (!interactive) {
          _showMessage('自动同步发现冲突，请手动同步后处理。');
          return SyncRunOutcome.conflict(result);
        }
        await _handleSyncConflicts(
          conflictPaths: result.conflictPaths,
          remoteSource: remoteSource,
          provider: SyncProvider.oneDrive,
          attachmentPolicy: AttachmentSyncPolicy(
            syncOriginals: _oneDriveConfig!.syncOriginals,
            downloadOriginals: _oneDriveConfig!.downloadOriginals,
          ),
          setSyncing: (value) {
            if (!mounted) {
              return;
            }
            setState(() {
              _setOneDriveSyncing(value);
            });
          },
        );
        return SyncRunOutcome.conflict(result);
      }

      if (interactive) {
        await _showSyncResultDialog(sourceLabel: 'OneDrive', result: result);
      }
      return SyncRunOutcome.success(result);
    } on SyncSafetyException catch (error) {
      await _recordSyncFailure(SyncProvider.oneDrive, error.message);
      if (mounted) {
        _showMessage(error.message);
      }
      return SyncRunOutcome.failed(error.message);
    } on OneDriveAuthException catch (error) {
      await _recordSyncFailure(SyncProvider.oneDrive, error.message);
      if (mounted) {
        _showMessage(error.message);
      }
      return SyncRunOutcome.failed(error.message);
    } on TimeoutException {
      const message = 'OneDrive 同步超时，请检查网络后重试。';
      await _recordSyncFailure(SyncProvider.oneDrive, message);
      if (mounted) {
        _showMessage(message);
      }
      return SyncRunOutcome.failed(message);
    } catch (error) {
      final message = 'OneDrive 同步失败：$error';
      await _recordSyncFailure(SyncProvider.oneDrive, message);
      if (mounted) {
        _showMessage(message);
      }
      return SyncRunOutcome.failed(message);
    } finally {
      await SyncForegroundGuard.stop();
      if (mounted) {
        setState(() {
          _setOneDriveSyncing(false);
          _oneDriveSyncProgress = null;
          _oneDriveSyncLabel = null;
          _syncStartedAt = null;
          _lastForegroundUpdateAt = null;
        });
        _syncStatusRevision.value += 1;
      }
    }
  }

  Future<bool> _disconnectOneDrive() async {
    if (_oneDriveConfig == null ||
        _isConnectingOneDrive ||
        _isSyncingOneDrive) {
      if (_isSyncingOneDrive) {
        _showMessage('同步中，断开连接稍后再操作。');
      }
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('断开 OneDrive'),
          content: const Text('这只会移除当前设备上的 OneDrive 登录状态，不会删除本地数据或云端文件。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('断开'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return false;
    }

    await _oneDriveAuthService().disconnect();
    if (!mounted) {
      return false;
    }

    setState(() {
      _oneDriveConfig = null;
      _lastSyncedAt = null;
      _lastSyncFailedAt = null;
      _lastSyncFailureMessage = null;
    });
    _showMessage('已断开 OneDrive');
    return true;
  }

  Future<void> _triggerAutoSync({required String reason}) async {
    if (_isConnectingOneDrive || _isSyncingOneDrive) {
      return;
    }

    final config = _oneDriveConfig;
    if (config == null || !config.syncOnWrite) {
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

    final outcome = await _syncWithOneDrive(interactive: false);
    if (mounted && outcome.isSuccess) {
      _showMessage('已经把小日子放到云端了');
    }
  }

  Future<void> _recordSyncFailure(SyncProvider provider, String message) async {
    final currentState = await widget.storage.loadSyncState(provider);
    final failedState = currentState.copyWith(
      lastFailedAt: DateTime.now(),
      lastFailureMessage: message,
    );
    await widget.storage.saveSyncState(failedState, provider);
    if (provider == SyncProvider.oneDrive && mounted) {
      setState(() {
        _lastSyncFailedAt = failedState.lastFailedAt;
        _lastSyncFailureMessage = failedState.lastFailureMessage;
      });
    }
  }

  Future<void> _handleSyncConflicts({
    required List<String> conflictPaths,
    required DiarySyncRemoteSource remoteSource,
    required SyncProvider provider,
    AttachmentSyncPolicy attachmentPolicy = const AttachmentSyncPolicy(),
    required void Function(bool value) setSyncing,
  }) async {
    final result = await Navigator.of(context)
        .push<SyncConflictResolutionResult>(
          MaterialPageRoute(
            builder: (_) => SyncConflictPage(conflictPaths: conflictPaths),
          ),
        );

    if (result == null || !mounted) {
      return;
    }

    setSyncing(true);

    try {
      final executor = DiarySyncExecutor(
        storage: widget.storage,
        remoteSource: remoteSource,
        provider: provider,
        attachmentPolicy: attachmentPolicy,
      );
      await executor.resolveConflicts(
        preferLocalByPath: {
          for (final entry in result.decisions.entries)
            entry.key: entry.value == SyncConflictResolutionChoice.keepLocal,
        },
      );
      await _loadAppData();
      if (!mounted) {
        return;
      }
      _showMessage('已按你的选择处理冲突');
    } on OneDriveAuthException catch (error) {
      await _recordSyncFailure(provider, error.message);
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error) {
      await _recordSyncFailure(provider, '处理冲突失败：$error');
      if (mounted) {
        _showMessage('处理冲突失败：$error');
      }
    } finally {
      setSyncing(false);
    }
  }

  Future<void> _startStartupOneDriveRestore() async {
    if (_startupRestoreRequested) {
      return;
    }

    setState(() {
      _startupRestoreRequested = true;
    });
    _selectTab(2, animate: false);

    if (_oneDriveConfig == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showMessage('已进入主页面。请手动连接 OneDrive，连接完成后会自动开始恢复。');
        }
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_restoreFromOneDriveAtStartup());
      }
    });
  }

  Future<void> _restoreFromOneDriveAtStartup() async {
    if (_oneDriveConfig == null || _isSyncingOneDrive) {
      return;
    }

    const initialRestoreLabel = '准备恢复：读取 OneDrive 数据';
    setState(() {
      _setOneDriveSyncing(true);
      _syncStartedAt = DateTime.now();
      _syncStatusHistory.clear();
      _recordSyncStatus(0, initialRestoreLabel);
      _syncWaitingMessage = randomSyncWaitingMessage();
      _lastForegroundUpdateAt = null;
    });

    try {
      await _yieldToUi();
      await SyncForegroundGuard.start(label: initialRestoreLabel, progress: 0);
      _lastForegroundUpdateAt = DateTime.now();
      await _yieldToUi();
      final remoteSource = _oneDriveRemoteSource();
      final snapshot = await remoteSource.fetchSnapshot(
        baseline: await widget.storage.loadSyncState(SyncProvider.oneDrive),
        onProgress: (remoteProgress, label) {
          final mappedProgress = 0.05 + remoteProgress.clamp(0, 1) * 0.25;
          unawaited(
            _updateForegroundSyncStatus(label: label, progress: mappedProgress),
          );
          if (!mounted) {
            return;
          }
          _recordSyncStatus(mappedProgress, label);
        },
      );
      final attachmentPolicy = AttachmentSyncPolicy(
        syncOriginals: _oneDriveConfig!.syncOriginals,
        downloadOriginals: _oneDriveConfig!.downloadOriginals,
      );
      final filesToRestore = snapshot.files
          .where(
            (file) => attachmentPolicy.includeRemotePath(file.relativePath),
          )
          .toList();
      if (filesToRestore.isEmpty) {
        if (mounted) {
          _showMessage('OneDrive 里还没有可恢复的数据。');
        }
        return;
      }

      for (var index = 0; index < filesToRestore.length; index++) {
        final file = filesToRestore[index];
        final progress = 0.35 + ((index + 1) / filesToRestore.length) * 0.45;
        final label =
            '恢复下载 ${index + 1}/${filesToRestore.length}：${file.relativePath}';
        unawaited(
          _updateForegroundSyncStatus(label: label, progress: progress),
        );
        if (mounted) {
          _recordSyncStatus(progress, label);
        }
        final targetAbsolutePath = await widget.storage
            .resolveSyncFileAbsolutePath(file.relativePath);
        final targetFile = File(targetAbsolutePath);
        final parent = targetFile.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await remoteSource.downloadFile(
          relativePath: file.relativePath,
          targetAbsolutePath: targetAbsolutePath,
          isBinary: file.isBinary,
        );
      }

      final localFiles = (await widget.storage.listSyncFiles())
          .where((file) => attachmentPolicy.includeLocalPath(file.relativePath))
          .toList();
      await widget.storage.saveSyncState(
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
      await _loadAppData();

      if (mounted) {
        _recordSyncStatus(
          1,
          '恢复完成：已从 OneDrive 下载 ${filesToRestore.length} 个文件',
        );
        _showMessage('已从 OneDrive 恢复本地数据。');
      }
    } on OneDriveAuthException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('恢复失败：$error');
      }
    } finally {
      await SyncForegroundGuard.stop();
      if (mounted) {
        setState(() {
          _setOneDriveSyncing(false);
          _oneDriveSyncProgress = null;
          _oneDriveSyncLabel = null;
          _syncStartedAt = null;
          _lastForegroundUpdateAt = null;
        });
        _syncStatusRevision.value += 1;
      }
    }
  }

  Future<_OneDriveConfigFormData?> _showOneDriveConfigPage(
    _OneDriveConfigFormData defaults,
  ) async {
    return Navigator.of(context).push<_OneDriveConfigFormData>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _OneDriveSyncSettingsPage(
          defaults: defaults,
          onDisconnect: _disconnectOneDrive,
          onCleanLocalOriginals: (olderThan) =>
              widget.storage.purgeLocalOriginals(olderThan: olderThan),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSyncResultDialog({
    required String sourceLabel,
    required SyncExecutionResult result,
  }) async {
    if (!mounted) {
      return;
    }

    final changedPaths = <String>[
      ...result.uploadedPaths.map((path) => '上传  $path'),
      ...result.downloadedPaths.map((path) => '下载  $path'),
      ...result.deletedRemotePaths.map((path) => '远端删除  $path'),
      ...result.deletedLocalPaths.map((path) => '本地删除  $path'),
    ];
    final previewPaths = changedPaths.take(6).toList();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$sourceLabel 同步完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '上传 ${result.uploadedPaths.length}，下载 ${result.downloadedPaths.length}，远端删除 ${result.deletedRemotePaths.length}，本地删除 ${result.deletedLocalPaths.length}',
              ),
              if (previewPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('本次变更'),
                const SizedBox(height: 8),
                ...previewPaths.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(path),
                  ),
                ),
                if (changedPaths.length > previewPaths.length) ...[
                  const SizedBox(height: 4),
                  Text('还有 ${changedPaths.length - previewPaths.length} 项未展开'),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSyncStatusDetails() async {
    final startedAt = _syncStartedAt;
    final history = List<_SyncStatusEntry>.from(_syncStatusHistory.reversed);
    if (history.isEmpty && _oneDriveSyncLabel != null) {
      history.add(
        _SyncStatusEntry(
          label: _oneDriveSyncLabel!,
          progress: _oneDriveSyncProgress ?? 0,
          recordedAt: DateTime.now(),
        ),
      );
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final elapsed = startedAt == null
            ? null
            : DateTime.now().difference(startedAt).inSeconds;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '同步详情',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: DiaryPalette.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  elapsed == null
                      ? 'OneDrive 正在同步，当前只锁定写入操作'
                      : '已运行 ${elapsed}s，当前只锁定写入操作',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: DiaryPalette.wine),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, _) => const Divider(height: 18),
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final percent = (item.progress.clamp(0, 1) * 100).round();
                      final elapsedSeconds = startedAt == null
                          ? null
                          : item.recordedAt.difference(startedAt).inSeconds;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DiaryBadge(
                            label: '$percent%',
                            tone: index == 0
                                ? DiaryBadgeTone.rose
                                : DiaryBadgeTone.ink,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.label,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: DiaryPalette.wine,
                                        height: 1.35,
                                      ),
                                ),
                                if (elapsedSeconds != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '+${elapsedSeconds}s',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: DiaryPalette.wine.withValues(
                                            alpha: 0.68,
                                          ),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSyncStatusBanner() {
    if (!_isSyncingOneDrive) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: _syncStatusRevision,
      builder: (context, _, _) {
        final percent = _oneDriveSyncProgress == null
            ? null
            : '${(_oneDriveSyncProgress!.clamp(0, 1) * 100).round()}%';

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DiaryPalette.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: DiaryPalette.white.withValues(alpha: 0.72),
              ),
              boxShadow: [
                BoxShadow(
                  color: DiaryPalette.rose.withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_sync_rounded,
                        color: DiaryPalette.rose,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _oneDriveSyncLabel ?? 'OneDrive 正在同步',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: DiaryPalette.ink,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      if (percent != null) ...[
                        const SizedBox(width: 8),
                        DiaryBadge(label: percent, tone: DiaryBadgeTone.rose),
                      ],
                      const SizedBox(width: 8),
                      const DiaryBadge(label: '只读中', tone: DiaryBadgeTone.ink),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _oneDriveSyncProgress),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _syncWaitingMessage,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: DiaryPalette.wine),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: DiaryPalette.wine,
                          minimumSize: Size.zero,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: _showSyncStatusDetails,
                        icon: const Icon(Icons.list_alt_rounded, size: 18),
                        label: const Text('同步详情'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingTabBar() {
    return Positioned(
      left: 28,
      right: 28,
      bottom: MediaQuery.paddingOf(context).bottom + 16,
      child: _FloatingTabBar(
        currentIndex: _currentIndex,
        pageController: _pageController,
        onSelected: _selectTab,
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    final isSyncBusy = _isConnectingOneDrive || _isSyncingOneDrive;
    final isWriteLocked = _isWriteLocked;
    final hasOneDrive = _oneDriveConfig != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 86,
        right: 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'sync-action',
            backgroundColor: DiaryPalette.rose.withValues(alpha: 0.88),
            foregroundColor: DiaryPalette.white,
            elevation: 8,
            onPressed: isSyncBusy
                ? null
                : hasOneDrive
                ? () => unawaited(_syncWithOneDrive())
                : () => _connectOneDrive(),
            icon: Icon(
              hasOneDrive ? Icons.sync_rounded : Icons.cloud_sync_rounded,
            ),
            label: Text(
              _isSyncingOneDrive
                  ? '同步中...'
                  : hasOneDrive
                  ? '同步'
                  : '连接',
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'write-action',
            backgroundColor: DiaryPalette.rose.withValues(alpha: 0.88),
            foregroundColor: DiaryPalette.white,
            elevation: 8,
            onPressed: isWriteLocked
                ? _showWriteLockedMessage
                : () => _openEditor(),
            icon: Icon(
              isWriteLocked
                  ? Icons.visibility_rounded
                  : Icons.edit_note_rounded,
            ),
            label: Text(isWriteLocked ? '只能查看' : '写日记'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_profile.isOnboarded && !_startupRestoreRequested) {
      return ProfileSetupPage(
        initialProfile: _profile,
        isFirstSetup: true,
        canRestoreFromOneDrive: _shouldOfferStartupRecovery(
          entries: _entries,
          profile: _profile,
        ),
        hasOneDriveConfig: _oneDriveConfig != null,
        onRestoreFromOneDrive: _startStartupOneDriveRestore,
        onComplete: (profile) async {
          setState(() {
            _profile = profile;
          });
          await _persistProfile();
        },
      );
    }

    final pages = [
      RealTodayTab(
        profile: _profile,
        entries: _entries,
        startupQuote: _startupQuote,
      ),
      RealTimelineTab(
        entries: _entries,
        rootDirectoryPath: _storageRootPath,
        isWriteLocked: _isWriteLocked,
        onWriteBlocked: _showWriteLockedMessage,
        onOpenEntry: _openEntryDetail,
        onEditEntry: _editEntry,
        onDeleteEntry: _deleteEntry,
      ),
      RealUsTab(
        profile: _profile,
        entries: _entries,
        oneDriveConfig: _oneDriveConfig,
        lastSyncedAt: _lastSyncedAt,
        lastSyncFailedAt: _lastSyncFailedAt,
        lastSyncFailureMessage: _lastSyncFailureMessage,
        onEditProfile: () => _openProfileEditor(firstSetup: false),
        onOpenDustbin: _openDustbin,
        onConnectOneDrive: _connectOneDrive,
        onOpenOneDriveSettings: _openOneDriveSettings,
      ),
    ];

    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const Positioned.fill(child: DiaryBackground()),
          Positioned.fill(
            child: PageView(
              controller: _pageController,
              clipBehavior: Clip.hardEdge,
              physics: const _DeliberatePageScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              allowImplicitScrolling: true,
              onPageChanged: (index) {
                if (_currentIndex == index) {
                  return;
                }
                setState(() {
                  _currentIndex = index;
                });
              },
              children: [for (final page in pages) _KeepAlivePage(child: page)],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: topInset + 10,
            child: IgnorePointer(
              ignoring: !_isSyncingOneDrive && _startupLoadError == null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStartupErrorBanner(),
                  _buildSyncStatusBanner(),
                ],
              ),
            ),
          ),
          _buildFloatingTabBar(),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _DeliberatePageScrollPhysics extends PageScrollPhysics {
  const _DeliberatePageScrollPhysics({super.parent});

  @override
  _DeliberatePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _DeliberatePageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 96;

  @override
  double get minFlingVelocity => 900;

  @override
  double? get dragStartDistanceMotionThreshold => 18;
}

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.currentIndex,
    required this.pageController,
    required this.onSelected,
  });

  final int currentIndex;
  final PageController pageController;
  final ValueChanged<int> onSelected;

  static const _items = [
    _FloatingTabSpec(
      label: '今天',
      icon: Icons.favorite_border_rounded,
      selectedIcon: Icons.favorite_rounded,
    ),
    _FloatingTabSpec(
      label: '回忆',
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories_rounded,
    ),
    _FloatingTabSpec(
      label: '我们',
      icon: Icons.people_alt_outlined,
      selectedIcon: Icons.people_alt_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DiaryPalette.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: DiaryPalette.white.withValues(alpha: 0.82)),
        boxShadow: [
          BoxShadow(
            color: DiaryPalette.ink.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: SizedBox(
          height: 68,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const inset = 6.0;
              final itemWidth =
                  (constraints.maxWidth - inset * 2) / _items.length;

              return AnimatedBuilder(
                animation: pageController,
                builder: (context, _) {
                  final rawPage = pageController.hasClients
                      ? pageController.page ?? currentIndex.toDouble()
                      : currentIndex.toDouble();
                  final page = rawPage
                      .clamp(0.0, (_items.length - 1).toDouble())
                      .toDouble();

                  return Stack(
                    children: [
                      Positioned(
                        top: inset,
                        bottom: inset,
                        left: inset + itemWidth * page,
                        width: itemWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: DiaryPalette.mist.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(inset),
                        child: Row(
                          children: [
                            for (var index = 0; index < _items.length; index++)
                              Expanded(
                                child: _FloatingTabButton(
                                  spec: _items[index],
                                  selection: (1 - (page - index).abs())
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  selected: currentIndex == index,
                                  onTap: () => onSelected(index),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FloatingTabSpec {
  const _FloatingTabSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _FloatingTabButton extends StatelessWidget {
  const _FloatingTabButton({
    required this.spec,
    required this.selection,
    required this.selected,
    required this.onTap,
  });

  final _FloatingTabSpec spec;
  final double selection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        Color.lerp(DiaryPalette.wine, DiaryPalette.rose, selection) ??
        DiaryPalette.wine;
    final weight = selection > 0.5 ? FontWeight.w900 : FontWeight.w700;
    return Semantics(
      selected: selected,
      button: true,
      label: spec.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            scale: 1 + selection * 0.035,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selection > 0.5 ? spec.selectedIcon : spec.icon,
                  color: foreground,
                  size: 22,
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  style:
                      Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: weight,
                      ) ??
                      TextStyle(color: foreground, fontWeight: weight),
                  child: Text(spec.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DustbinPage extends StatefulWidget {
  const DustbinPage({
    super.key,
    required this.storage,
    required this.writeLockedListenable,
    required this.onWriteBlocked,
  });

  final DiaryStorage storage;
  final ValueListenable<bool> writeLockedListenable;
  final VoidCallback onWriteBlocked;

  @override
  State<DustbinPage> createState() => _DustbinPageState();
}

class _DustbinPageState extends State<DustbinPage> {
  List<DeletedDiaryEntry> _deletedEntries = const [];
  bool _isLoading = true;
  String? _processingEntryId;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    widget.writeLockedListenable.addListener(_handleWriteLockChanged);
    _loadDeletedEntries();
  }

  @override
  void dispose() {
    widget.writeLockedListenable.removeListener(_handleWriteLockChanged);
    super.dispose();
  }

  bool get _isWriteLocked => widget.writeLockedListenable.value;

  void _handleWriteLockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _guardWritableAction() {
    if (!_isWriteLocked) {
      return true;
    }
    widget.onWriteBlocked();
    return false;
  }

  Future<void> _loadDeletedEntries() async {
    final deletedEntries = await widget.storage.loadDustbinEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _deletedEntries = deletedEntries;
      _isLoading = false;
    });
  }

  Future<void> _restoreEntry(DeletedDiaryEntry deletedEntry) async {
    if (!_guardWritableAction()) {
      return;
    }

    setState(() {
      _processingEntryId = deletedEntry.entry.id;
    });

    await widget.storage.restoreDeletedEntry(deletedEntry);
    _hasChanged = true;
    await _loadDeletedEntries();

    if (!mounted) {
      return;
    }
    setState(() {
      _processingEntryId = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已恢复 ${deletedEntry.entry.title}')));
  }

  Future<void> _deleteForever(DeletedDiaryEntry deletedEntry) async {
    if (!_guardWritableAction()) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('彻底删除这篇日记？'),
          content: const Text('这次删除不会进入新的回收站，也不能再恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('彻底删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _processingEntryId = deletedEntry.entry.id;
    });

    await widget.storage.permanentlyDeleteDeletedEntry(deletedEntry);
    _hasChanged = true;
    await _loadDeletedEntries();

    if (!mounted) {
      return;
    }
    setState(() {
      _processingEntryId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已彻底删除 ${deletedEntry.entry.title}')),
    );
  }

  int _remainingDays(DeletedDiaryEntry deletedEntry) {
    final expiresAt = deletedEntry.deletedAt.add(const Duration(days: 7));
    final difference = expiresAt.difference(DateTime.now());
    if (difference.isNegative) {
      return 0;
    }
    return difference.inDays + 1;
  }

  void _closePage() {
    Navigator.of(context).pop(_hasChanged);
  }

  @override
  Widget build(BuildContext context) {
    final isWriteLocked = _isWriteLocked;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('回收站'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : DiaryPage(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: _deletedEntries.isEmpty
                  ? const DiaryEmptyState(
                      title: '回收站是空的',
                      subtitle: '删除后的日记会先放在这里，7 天后才会真正清理。',
                      icon: Icons.restore_from_trash_rounded,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DiaryHero(
                          eyebrow: '删除保护',
                          title: '最近删除的日记',
                          subtitle: '你可以在 7 天内恢复，也可以直接彻底删除。',
                        ),
                        const SizedBox(height: 20),
                        ..._deletedEntries.map((deletedEntry) {
                          final entry = deletedEntry.entry;
                          final isProcessing = _processingEntryId == entry.id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: DiaryPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                color: DiaryPalette.ink,
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      ),
                                      if (isProcessing)
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.summary,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: DiaryPalette.wine,
                                          height: 1.5,
                                        ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      DiaryBadge(label: entry.mood),
                                      DiaryBadge(
                                        label:
                                            '删除于 ${formatDiaryDate(deletedEntry.deletedAt)}',
                                        tone: DiaryBadgeTone.ink,
                                      ),
                                      DiaryBadge(
                                        label: '${entry.attachments.length} 张图',
                                        tone: DiaryBadgeTone.sand,
                                      ),
                                      DiaryBadge(
                                        label: '${entry.commentCount} 条评论',
                                        tone: DiaryBadgeTone.ink,
                                      ),
                                      DiaryBadge(
                                        label:
                                            '剩余 ${_remainingDays(deletedEntry)} 天',
                                        tone: DiaryBadgeTone.sand,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: isProcessing
                                            ? null
                                            : isWriteLocked
                                            ? widget.onWriteBlocked
                                            : () => _restoreEntry(deletedEntry),
                                        icon: const Icon(Icons.undo_rounded),
                                        label: const Text('恢复'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: isProcessing
                                            ? null
                                            : isWriteLocked
                                            ? widget.onWriteBlocked
                                            : () =>
                                                  _deleteForever(deletedEntry),
                                        icon: const Icon(
                                          Icons.delete_forever_rounded,
                                        ),
                                        label: const Text('彻底删除'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
            ),
    );
  }
}

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({
    super.key,
    required this.initialProfile,
    required this.isFirstSetup,
    this.canRestoreFromOneDrive = false,
    this.hasOneDriveConfig = false,
    this.onRestoreFromOneDrive,
    this.onComplete,
    this.writeLockedListenable,
    this.onWriteBlocked,
  });

  final CoupleProfile initialProfile;
  final bool isFirstSetup;
  final bool canRestoreFromOneDrive;
  final bool hasOneDriveConfig;
  final Future<void> Function()? onRestoreFromOneDrive;
  final Future<void> Function(CoupleProfile profile)? onComplete;
  final ValueListenable<bool>? writeLockedListenable;
  final VoidCallback? onWriteBlocked;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _maleNameController;
  late final TextEditingController _femaleNameController;
  late DateTime _togetherSince;
  late String _currentUserRole;

  @override
  void initState() {
    super.initState();
    widget.writeLockedListenable?.addListener(_handleWriteLockChanged);
    _maleNameController = TextEditingController(
      text: widget.initialProfile.maleName,
    );
    _femaleNameController = TextEditingController(
      text: widget.initialProfile.femaleName,
    );
    _togetherSince = widget.initialProfile.togetherSince;
    _currentUserRole = widget.initialProfile.currentUserRole;
  }

  @override
  void dispose() {
    widget.writeLockedListenable?.removeListener(_handleWriteLockChanged);
    _maleNameController.dispose();
    _femaleNameController.dispose();
    super.dispose();
  }

  bool get _isWriteLocked => widget.writeLockedListenable?.value ?? false;

  void _handleWriteLockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _guardWritableAction() {
    if (!_isWriteLocked) {
      return true;
    }
    widget.onWriteBlocked?.call();
    return false;
  }

  Future<void> _pickTogetherSince() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _togetherSince,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      helpText: '选择在一起的日期',
      cancelText: '取消',
      confirmText: '确定',
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _togetherSince = picked;
    });
  }

  Future<void> _submit() async {
    if (!_guardWritableAction()) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final profile = widget.initialProfile.copyWith(
      maleName: _maleNameController.text.trim(),
      femaleName: _femaleNameController.text.trim(),
      currentUserRole: _currentUserRole,
      togetherSince: _togetherSince,
      isOnboarded: true,
    );

    if (widget.onComplete != null) {
      await widget.onComplete!(profile);
      return;
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final isWriteLocked = _isWriteLocked;
    return Scaffold(
      appBar: widget.isFirstSetup ? null : AppBar(title: const Text('编辑我们')),
      body: SafeArea(
        top: widget.isFirstSetup,
        bottom: false,
        child: Form(
          key: _formKey,
          child: DiaryPage(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DiaryHero(
                  eyebrow: widget.isFirstSetup ? '初始设置' : '编辑资料',
                  title: widget.isFirstSetup ? '先把资料填好' : '更新资料',
                  subtitle: widget.isFirstSetup
                      ? '把名字和在一起的日期填好，首页和统计会自动带上这些信息。'
                      : '这些信息会影响首页展示、统计和纪念日标记。',
                ),
                if (widget.isFirstSetup &&
                    widget.canRestoreFromOneDrive &&
                    widget.onRestoreFromOneDrive != null) ...[
                  const SizedBox(height: 20),
                  DiaryPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已有 OneDrive 数据？',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: DiaryPalette.ink,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.hasOneDriveConfig
                              ? '可以先进入主页面并从 OneDrive 恢复，云端资料拉下来后会自动更新这里。'
                              : '可以先进入主页面，之后在“我们”页手动连接 OneDrive，连接完成后自动恢复已有数据。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: DiaryPalette.wine,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: widget.onRestoreFromOneDrive,
                          icon: const Icon(Icons.cloud_download_rounded),
                          label: const Text('从 OneDrive 恢复'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                DiaryPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _maleNameController,
                        decoration: const InputDecoration(labelText: '他叫什么'),
                        validator: _nonEmptyValidator,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _femaleNameController,
                        decoration: const InputDecoration(labelText: '她叫什么'),
                        validator: _nonEmptyValidator,
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'male',
                            label: Text('我是他'),
                          ),
                          ButtonSegment<String>(
                            value: 'female',
                            label: Text('我是她'),
                          ),
                        ],
                        selected: {_currentUserRole},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _currentUserRole = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pickTogetherSince,
                        icon: const Icon(Icons.favorite_rounded),
                        label: Text(
                          '在一起的日期：${formatDiaryDate(_togetherSince)}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: isWriteLocked ? widget.onWriteBlocked : _submit,
                  child: Text(
                    isWriteLocked
                        ? '同步中，稍后保存'
                        : widget.isFirstSetup
                        ? '开始记录'
                        : '保存资料',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _nonEmptyValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '这里不能为空';
    }
    return null;
  }
}

class EntryDetailPage extends StatefulWidget {
  const EntryDetailPage({
    super.key,
    required this.profile,
    required this.entry,
    required this.rootDirectoryPath,
    required this.writeLockedListenable,
    required this.onWriteBlocked,
    required this.onAddComment,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final CoupleProfile profile;
  final DiaryEntry entry;
  final String? rootDirectoryPath;
  final ValueListenable<bool> writeLockedListenable;
  final VoidCallback onWriteBlocked;
  final Future<DiaryEntry> Function(String entryId, DiaryComment comment)
  onAddComment;
  final Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry;
  final Future<void> Function(DiaryEntry entry) onDeleteEntry;

  @override
  State<EntryDetailPage> createState() => _EntryDetailPageState();
}

class _EntryDetailPageState extends State<EntryDetailPage> {
  final TextEditingController _commentController = TextEditingController();

  late DiaryEntry _entry;
  bool _isSavingComment = false;

  @override
  void initState() {
    super.initState();
    widget.writeLockedListenable.addListener(_handleWriteLockChanged);
    _entry = widget.entry;
  }

  @override
  void dispose() {
    widget.writeLockedListenable.removeListener(_handleWriteLockChanged);
    _commentController.dispose();
    super.dispose();
  }

  bool get _isWriteLocked => widget.writeLockedListenable.value;

  void _handleWriteLockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _guardWritableAction() {
    if (!_isWriteLocked) {
      return true;
    }
    widget.onWriteBlocked();
    return false;
  }

  Future<void> _submitComment() async {
    if (!_guardWritableAction()) {
      return;
    }

    final content = _commentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先写点内容再发表评论')));
      return;
    }

    setState(() {
      _isSavingComment = true;
    });

    try {
      final updatedEntry = await widget.onAddComment(
        _entry.id,
        DiaryComment(
          author: widget.profile.currentUserPronoun,
          content: content,
          createdAt: DateTime.now(),
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _entry = updatedEntry;
        _commentController.clear();
        _isSavingComment = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingComment = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评论保存失败，请稍后再试')));
    }
  }

  Future<void> _editEntry() async {
    if (!_guardWritableAction()) {
      return;
    }

    final updatedEntry = await widget.onEditEntry(_entry);
    if (updatedEntry == null || !mounted) {
      return;
    }

    setState(() {
      _entry = updatedEntry;
    });
  }

  Future<void> _deleteEntry() async {
    if (!_guardWritableAction()) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这篇日记？'),
          content: Text('《${_entry.title}》会从本地移除，并记录删除状态以便后续同步。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await widget.onDeleteEntry(_entry);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isWriteLocked = _isWriteLocked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日记详情'),
        actions: [
          IconButton(
            onPressed: isWriteLocked ? widget.onWriteBlocked : _editEntry,
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑日记',
          ),
          IconButton(
            onPressed: isWriteLocked ? widget.onWriteBlocked : _deleteEntry,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除日记',
          ),
        ],
      ),
      body: DiaryPage(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DiaryHero(
              eyebrow: '日记详情',
              title: _entry.title,
              subtitle: _entry.content,
              footer: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DiaryBadge(label: _entry.author, tone: DiaryBadgeTone.sand),
                  DiaryBadge(label: _entry.mood),
                  DiaryBadge(
                    label: formatDiaryDate(_entry.createdAt),
                    tone: DiaryBadgeTone.ink,
                  ),
                  DiaryBadge(
                    label: '${_entry.attachments.length} 张图',
                    tone: DiaryBadgeTone.sand,
                  ),
                  if (_entry.updatedAt != null)
                    DiaryBadge(
                      label: '最近更新 ${formatDiaryShortDate(_entry.updatedAt!)}',
                      tone: DiaryBadgeTone.ink,
                    ),
                ],
              ),
            ),
            if (_entry.attachments.isNotEmpty) ...[
              const SizedBox(height: 22),
              const DiarySectionHeader(
                title: '附图',
                subtitle: '先保留本地图片和预览，后续再继续优化同步体验。',
              ),
              const SizedBox(height: 12),
              DiaryPanel(
                child: AttachmentGrid(
                  attachments: _entry.attachments,
                  rootDirectoryPath: widget.rootDirectoryPath,
                ),
              ),
            ],
            const SizedBox(height: 22),
            const DiarySectionHeader(
              title: '评论区',
              subtitle: '评论会和这篇日记一起保存到本地，再由同步层决定何时上传。',
            ),
            const SizedBox(height: 12),
            DiaryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '将以 ${widget.profile.currentUserPronoun} 的身份发表评论。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: DiaryPalette.wine),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _commentController,
                    enabled: !isWriteLocked,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '写一条评论',
                      hintText: '比如：这个瞬间我也想一直记得。',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSavingComment
                          ? null
                          : isWriteLocked
                          ? widget.onWriteBlocked
                          : _submitComment,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text(
                        _isSavingComment
                            ? '保存中...'
                            : isWriteLocked
                            ? '同步中，稍后评论'
                            : '发表评论',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_entry.comments.isEmpty)
              const DiaryEmptyState(
                title: '还没有评论',
                subtitle: '可以先从一句简单的回应开始。',
                icon: Icons.chat_bubble_outline_rounded,
              )
            else
              ..._entry.comments.map(
                (comment) => CommentCard(comment: comment),
              ),
          ],
        ),
      ),
    );
  }
}

class CreateEntryPage extends StatefulWidget {
  const CreateEntryPage({
    super.key,
    required this.storage,
    required this.profile,
    required this.writeLockedListenable,
    required this.onWriteBlocked,
    this.initialEntry,
    this.rootDirectoryPath,
  });

  final DiaryStorage storage;
  final CoupleProfile profile;
  final ValueListenable<bool> writeLockedListenable;
  final VoidCallback onWriteBlocked;
  final DiaryEntry? initialEntry;
  final String? rootDirectoryPath;

  @override
  State<CreateEntryPage> createState() => _CreateEntryPageState();
}

class _CreateEntryPageState extends State<CreateEntryPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final ImagePicker _imagePicker = ImagePicker();

  late DateTime _selectedDate;
  late String _selectedMood;
  bool _isPickingImages = false;
  bool _isPreparingDraft = true;
  List<DiaryAttachment> _attachments = [];
  DiaryDraft? _lastSavedDraft;
  late String _entryAuthor;

  bool get _isEditMode => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    widget.writeLockedListenable.addListener(_handleWriteLockChanged);
    _titleController = TextEditingController(
      text: widget.initialEntry?.title ?? '',
    );
    _contentController = TextEditingController(
      text: widget.initialEntry?.content ?? '',
    );
    _selectedDate = widget.initialEntry?.createdAt ?? DateTime.now();
    _selectedMood = widget.initialEntry?.mood ?? kDiaryMoods.first;
    _entryAuthor =
        widget.initialEntry?.author ?? widget.profile.currentUserPronoun;
    _attachments = List<DiaryAttachment>.from(
      widget.initialEntry?.attachments ?? const [],
    );
    if (_isEditMode) {
      _isPreparingDraft = false;
    } else {
      _restoreDraft();
    }
  }

  @override
  void dispose() {
    widget.writeLockedListenable.removeListener(_handleWriteLockChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  bool get _isWriteLocked => widget.writeLockedListenable.value;

  void _handleWriteLockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _guardWritableAction() {
    if (!_isWriteLocked) {
      return true;
    }
    widget.onWriteBlocked();
    return false;
  }

  Future<void> _restoreDraft() async {
    final draft = await widget.storage.loadEntryDraft();
    if (!mounted) {
      return;
    }

    if (draft != null) {
      _titleController.text = draft.title;
      _contentController.text = draft.content;
      _selectedDate = draft.selectedDate;
      _selectedMood = draft.mood;
      _attachments = List<DiaryAttachment>.from(draft.attachments);
      _lastSavedDraft = draft;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复上次未完成的草稿')));
      });
    }

    setState(() {
      _isPreparingDraft = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择日记日期',
      cancelText: '取消',
      confirmText: '确定',
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _selectedDate.hour,
        _selectedDate.minute,
      );
    });
  }

  Future<void> _pickImages() async {
    if (!_guardWritableAction()) {
      return;
    }

    if (kIsWeb) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('网页端图片保存这版先只支持安卓真机/模拟器')));
      return;
    }

    final importMode = await _showAttachmentImportModeSheet();
    if (!mounted || importMode == null) {
      return;
    }

    setState(() {
      _isPickingImages = true;
    });

    try {
      final files = await _imagePicker.pickMultiImage(
        imageQuality: importMode == _AttachmentImportMode.compressed
            ? 85
            : null,
        limit: 6,
      );

      if (files.isEmpty) {
        if (mounted) {
          setState(() {
            _isPickingImages = false;
          });
        }
        return;
      }

      final List<DiaryAttachment> savedAttachments = [];
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final savedAttachment = await widget.storage.importAttachment(
          sourcePath: file.path,
          fileName: '${index}_${file.name}',
          keepOriginal: importMode == _AttachmentImportMode.original,
        );
        savedAttachments.add(savedAttachment);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _attachments = [..._attachments, ...savedAttachments];
        _isPickingImages = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPickingImages = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片导入失败，请检查权限或稍后再试')));
    }
  }

  Future<void> _removeAttachment(DiaryAttachment attachment) async {
    if (!_guardWritableAction()) {
      return;
    }

    if (_isTemporaryAttachment(attachment)) {
      await widget.storage.deleteAttachments([attachment]);
    }

    setState(() {
      _attachments = _attachments
          .where((item) => item.id != attachment.id)
          .toList();
    });
  }

  Future<_AttachmentImportMode?> _showAttachmentImportModeSheet() {
    return showModalBottomSheet<_AttachmentImportMode>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导入图片',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '默认建议压缩导入。需要保留完整清晰度时，再选原图。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8D687C),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.data_saver_on_rounded),
                  title: const Text('节省流量'),
                  subtitle: const Text('压缩后导入，上传更省流量'),
                  onTap: () {
                    Navigator.of(context).pop(_AttachmentImportMode.compressed);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.high_quality_rounded),
                  title: const Text('原图导入'),
                  subtitle: const Text('保留原图质量，上传体积更大'),
                  onTap: () {
                    Navigator.of(context).pop(_AttachmentImportMode.original);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveDraft() async {
    if (!_guardWritableAction()) {
      return;
    }

    final draft = _currentDraft();
    if (_isDraftEmpty(draft)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先写一点内容再保存草稿')));
      return;
    }

    await widget.storage.saveEntryDraft(draft);
    _lastSavedDraft = draft;
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('草稿已保存')));
  }

  bool get _isDirty {
    if (_isEditMode) {
      final initialEntry = widget.initialEntry!;
      return _titleController.text.trim() != initialEntry.title ||
          _contentController.text.trim() != initialEntry.content ||
          _selectedMood != initialEntry.mood ||
          !isSameDay(_selectedDate, initialEntry.createdAt) ||
          !_sameAttachments(_attachments, initialEntry.attachments);
    }

    final currentDraft = _currentDraft();
    final baseline = _lastSavedDraft;
    if (baseline == null) {
      return !_isDraftEmpty(currentDraft);
    }

    return currentDraft.title != baseline.title ||
        currentDraft.content != baseline.content ||
        currentDraft.mood != baseline.mood ||
        !isSameDay(currentDraft.selectedDate, baseline.selectedDate) ||
        !_sameAttachments(currentDraft.attachments, baseline.attachments);
  }

  Future<bool> _confirmExit() async {
    if (!_isDirty) {
      return true;
    }

    final action = await showDialog<_EditorExitAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_isEditMode ? '放弃本次修改？' : '离开前要怎么处理？'),
          content: Text(_isEditMode ? '你刚刚修改的内容还没有保存。' : '这篇日记还没有保存，可以先存成草稿。'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_EditorExitAction.cancel),
              child: const Text('继续编辑'),
            ),
            if (!_isEditMode)
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_EditorExitAction.saveDraft),
                child: const Text('存为草稿'),
              ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_EditorExitAction.discard),
              child: const Text('放弃'),
            ),
          ],
        );
      },
    );

    switch (action) {
      case _EditorExitAction.saveDraft:
        if (_isWriteLocked) {
          widget.onWriteBlocked();
          return false;
        }
        await _saveDraft();
        return true;
      case _EditorExitAction.discard:
        if (_attachments.any(_isTemporaryAttachment) && _isWriteLocked) {
          widget.onWriteBlocked();
          return false;
        }
        await _discardTemporaryAttachments();
        return true;
      case _EditorExitAction.cancel:
      case null:
        return false;
    }
  }

  Future<void> _handleBack() async {
    final shouldPop = await _confirmExit();
    if (!mounted || !shouldPop) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (!_guardWritableAction()) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final originalCreatedAt = widget.initialEntry?.createdAt ?? now;

    final entry = DiaryEntry(
      id: widget.initialEntry?.id ?? 'entry_${now.microsecondsSinceEpoch}',
      author: _entryAuthor,
      title: title.isEmpty ? _guessTitle(content) : title,
      content: content,
      mood: _selectedMood,
      createdAt: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        originalCreatedAt.hour,
        originalCreatedAt.minute,
      ),
      updatedAt: _isEditMode ? now : null,
      comments: widget.initialEntry?.comments ?? const [],
      attachments: _attachments,
    );

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(entry);
  }

  DiaryDraft _currentDraft() {
    return DiaryDraft(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      mood: _selectedMood,
      selectedDate: _selectedDate,
      attachments: List<DiaryAttachment>.from(_attachments),
      savedAt: DateTime.now(),
    );
  }

  bool _isDraftEmpty(DiaryDraft draft) {
    return draft.title.isEmpty &&
        draft.content.isEmpty &&
        draft.attachments.isEmpty &&
        draft.mood == kDiaryMoods.first &&
        isSameDay(draft.selectedDate, DateTime.now());
  }

  Future<void> _discardTemporaryAttachments() async {
    final temporaryAttachments = _attachments
        .where(_isTemporaryAttachment)
        .toList();
    await widget.storage.deleteAttachments(temporaryAttachments);
    if (!_isEditMode) {
      await widget.storage.clearEntryDraft();
    }
  }

  bool _sameAttachments(
    List<DiaryAttachment> left,
    List<DiaryAttachment> right,
  ) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      final current = left[index];
      final baseline = right[index];
      if (current.id != baseline.id ||
          current.path != baseline.path ||
          current.thumbnailPath != baseline.thumbnailPath ||
          current.previewPath != baseline.previewPath ||
          current.originalPath != baseline.originalPath) {
        return false;
      }
    }
    return true;
  }

  bool _isTemporaryAttachment(DiaryAttachment attachment) {
    return attachment.storedPaths.any((path) => path.startsWith('drafts/'));
  }

  String _guessTitle(String content) {
    if (content.length <= 10) {
      return content;
    }
    return '${content.substring(0, 10)}...';
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreparingDraft) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isWriteLocked = _isWriteLocked;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(_isEditMode ? '编辑日记' : '新建日记'),
          actions: [
            if (!_isEditMode)
              TextButton(
                onPressed: isWriteLocked ? widget.onWriteBlocked : _saveDraft,
                child: Text(isWriteLocked ? '同步中' : '存草稿'),
              ),
            TextButton(
              onPressed: isWriteLocked ? widget.onWriteBlocked : _submit,
              child: Text(isWriteLocked ? '稍后保存' : '保存'),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: DiaryPage(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DiaryHero(
                  eyebrow: _isEditMode ? '编辑日记' : '新建日记',
                  title: _isEditMode ? '编辑这篇日记' : '写一篇新日记',
                  subtitle: _isEditMode
                      ? '支持修改标题、内容、心情、日期和附图，保存后会回到时间线。'
                      : '支持草稿、本地保存、附图和评论。',
                ),
                const SizedBox(height: 20),
                DiaryPanel(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [DiaryBadge(label: _entryAuthor)],
                  ),
                ),
                const SizedBox(height: 20),
                DiaryPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '标题（可选）',
                          hintText: '比如：今天一起散步',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _contentController,
                        minLines: 6,
                        maxLines: 10,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          labelText: '内容',
                          hintText: '写下今天发生的小事、心情，或者想对对方说的话。',
                          alignLabelWithHint: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '内容不能为空';
                          }
                          if (value.trim().length < 5) {
                            return '再多写一点，至少 5 个字';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const DiarySectionHeader(
                  title: '状态',
                  subtitle: '心情、日期和图片先决定这篇日记的外轮廓。',
                ),
                const SizedBox(height: 12),
                DiaryPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isPickingImages
                              ? null
                              : isWriteLocked
                              ? widget.onWriteBlocked
                              : _pickImages,
                          icon: const Icon(Icons.add_photo_alternate_rounded),
                          label: Text(
                            isWriteLocked
                                ? '同步中，稍后添加照片'
                                : _isPickingImages
                                ? '正在处理照片...'
                                : _attachments.isEmpty
                                ? '添加照片'
                                : '继续添加照片（已添加 ${_attachments.length} 张）',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: kDiaryMoods.map((mood) {
                          return ChoiceChip(
                            label: Text(mood),
                            selected: _selectedMood == mood,
                            onSelected: (_) {
                              setState(() {
                                _selectedMood = mood;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text('日记日期：${formatDiaryDate(_selectedDate)}'),
                      ),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        EditableAttachmentGrid(
                          attachments: _attachments,
                          rootDirectoryPath: widget.rootDirectoryPath,
                          onRemove: (attachment) {
                            if (isWriteLocked) {
                              widget.onWriteBlocked();
                              return;
                            }
                            _removeAttachment(attachment);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const DraftHintCard(),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isWriteLocked ? widget.onWriteBlocked : _submit,
                  icon: const Icon(Icons.favorite_rounded),
                  label: Text(
                    isWriteLocked
                        ? '同步中，稍后保存'
                        : _isEditMode
                        ? '保存修改'
                        : '保存这篇日记',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.profile,
    required this.entryCount,
  });

  final CoupleProfile profile;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final togetherDays =
        DateTime.now().difference(profile.togetherSince).inDays + 1;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5D1DC), Color(0xFFE7D8FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CoupleAvatar(label: profile.maleName.characters.first),
              const SizedBox(width: 10),
              CoupleAvatar(label: profile.femaleName.characters.first),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '第 $togetherDays 天',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF7A4A60),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${profile.maleName} & ${profile.femaleName}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF7A4A60),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '把今天的内容记下来。',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              InfoChip(label: '在一起', value: '$togetherDays 天'),
              InfoChip(label: '共同日记', value: '$entryCount 篇'),
              InfoChip(
                label: '纪念起点',
                value: formatShortDate(profile.togetherSince),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DraftHintCard extends StatelessWidget {
  const DraftHintCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DiaryPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: DiaryPalette.mist,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              color: DiaryPalette.rose,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '支持日记、附图、评论和本地保存。',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: DiaryPalette.wine,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: theme.textTheme.labelLarge?.copyWith(
            color: const Color(0xFFC85C8E),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF8D687C),
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF8D687C),
          ),
        ),
      ],
    );
  }
}

class CoupleAvatar extends StatelessWidget {
  const CoupleAvatar({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.white.withValues(alpha: 0.85),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF7A4A60),
        ),
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: const Color(0xFF8D687C)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class AttachmentGrid extends StatelessWidget {
  const AttachmentGrid({
    super.key,
    required this.attachments,
    required this.rootDirectoryPath,
    this.shrinkWrap = true,
    this.physics = const NeverScrollableScrollPhysics(),
  });

  final List<DiaryAttachment> attachments;
  final String? rootDirectoryPath;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: attachments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final attachment = attachments[index];
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AttachmentPreviewPage(
                  attachments: attachments,
                  rootDirectoryPath: rootDirectoryPath,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: DiaryAttachmentImage(
              attachment: attachment,
              rootDirectoryPath: rootDirectoryPath,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}

class EditableAttachmentGrid extends StatelessWidget {
  const EditableAttachmentGrid({
    super.key,
    required this.attachments,
    required this.rootDirectoryPath,
    required this.onRemove,
  });

  final List<DiaryAttachment> attachments;
  final String? rootDirectoryPath;
  final ValueChanged<DiaryAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: attachments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final attachment = attachments[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttachmentPreviewPage(
                      attachments: attachments,
                      rootDirectoryPath: rootDirectoryPath,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: DiaryAttachmentImage(
                  attachment: attachment,
                  rootDirectoryPath: rootDirectoryPath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: InkWell(
                onTap: () => onRemove(attachment),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class DiaryAttachmentImage extends StatelessWidget {
  const DiaryAttachmentImage({
    super.key,
    required this.attachment,
    required this.rootDirectoryPath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.preferOriginal = false,
  });

  final DiaryAttachment attachment;
  final String? rootDirectoryPath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool preferOriginal;

  @override
  Widget build(BuildContext context) {
    final path = preferOriginal
        ? attachment.originalOrFallbackPath
        : attachment.previewOrFallbackPath;
    if (path.isEmpty || kIsWeb) {
      return _AttachmentPlaceholder(width: width, height: height);
    }

    return Image.file(
      File(resolveStoredPath(rootDirectoryPath, path)),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) =>
          _AttachmentPlaceholder(width: width, height: height),
    );
  }
}

class AttachmentPreviewPage extends StatefulWidget {
  const AttachmentPreviewPage({
    super.key,
    required this.attachments,
    required this.rootDirectoryPath,
    required this.initialIndex,
  });

  final List<DiaryAttachment> attachments;
  final String? rootDirectoryPath;
  final int initialIndex;

  @override
  State<AttachmentPreviewPage> createState() => _AttachmentPreviewPageState();
}

class _AttachmentPreviewPageState extends State<AttachmentPreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachments[_currentIndex];
    final fileName = attachment.originalName.isEmpty
        ? '图片 ${_currentIndex + 1}'
        : attachment.originalName;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1}/${widget.attachments.length}'),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.attachments.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DiaryAttachmentImage(
                      attachment: widget.attachments[index],
                      rootDirectoryPath: widget.rootDirectoryPath,
                      fit: BoxFit.contain,
                      preferOriginal: true,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPlaceholder extends StatelessWidget {
  const _AttachmentPlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFFFEFF5),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Color(0xFFC85C8E)),
    );
  }
}

enum _EditorExitAction { cancel, saveDraft, discard }

enum _AttachmentImportMode { compressed, original }

class CommentCard extends StatelessWidget {
  const CommentCard({super.key, required this.comment});

  final DiaryComment comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DiaryPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: DiaryPalette.mist,
                  child: Text(
                    comment.author.characters.first,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: DiaryPalette.rose,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    comment.author,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: DiaryPalette.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${formatDiaryShortDate(comment.createdAt)} ${formatDiaryTime(comment.createdAt)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: DiaryPalette.wine),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              comment.content,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: DiaryPalette.wine,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EntryTag extends StatelessWidget {
  const EntryTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DiaryBadge(label: label);
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DiaryEmptyState(title: title, subtitle: subtitle);
  }
}

String formatDate(DateTime date) {
  return '${date.year} 年 ${date.month} 月 ${date.day} 日';
}

String formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatShortDate(DateTime date) {
  return '${date.month}/${date.day}';
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String resolveStoredPath(String? rootDirectoryPath, String storedPath) {
  final normalized = storedPath.replaceAll('\\', '/');
  final isAbsoluteUnix = normalized.startsWith('/');
  final isAbsoluteWindows = RegExp(r'^[a-zA-Z]:/').hasMatch(normalized);
  if (isAbsoluteUnix || isAbsoluteWindows || rootDirectoryPath == null) {
    return storedPath;
  }

  final normalizedRoot = rootDirectoryPath.replaceAll('\\', '/');
  return '$normalizedRoot/$normalized';
}

class _OneDriveConfigFormData {
  const _OneDriveConfigFormData({
    required this.remoteFolder,
    required this.syncOnWrite,
    required this.minimumSyncIntervalMinutes,
    required this.maxDestructiveActions,
    required this.syncOriginals,
    required this.downloadOriginals,
    required this.localOriginalRetentionDays,
  });

  final String remoteFolder;
  final bool syncOnWrite;
  final int minimumSyncIntervalMinutes;
  final int maxDestructiveActions;
  final bool syncOriginals;
  final bool downloadOriginals;
  final int localOriginalRetentionDays;
}

class _OneDriveSyncSettingsPage extends StatefulWidget {
  const _OneDriveSyncSettingsPage({
    required this.defaults,
    required this.onDisconnect,
    required this.onCleanLocalOriginals,
  });

  final _OneDriveConfigFormData defaults;
  final Future<bool> Function() onDisconnect;
  final Future<ImageCleanupResult> Function(Duration olderThan)
  onCleanLocalOriginals;

  @override
  State<_OneDriveSyncSettingsPage> createState() =>
      _OneDriveSyncSettingsPageState();
}

class _OneDriveSyncSettingsPageState extends State<_OneDriveSyncSettingsPage> {
  late final TextEditingController _remoteFolderController;
  late final TextEditingController _minimumIntervalController;
  late final TextEditingController _maxDestructiveActionsController;
  late final TextEditingController _localOriginalRetentionController;
  late bool _syncOnWrite;
  late bool _syncOriginals;
  late bool _downloadOriginals;
  bool _isCleaningOriginals = false;

  @override
  void initState() {
    super.initState();
    _remoteFolderController = TextEditingController(
      text: widget.defaults.remoteFolder,
    );
    _minimumIntervalController = TextEditingController(
      text: widget.defaults.minimumSyncIntervalMinutes.toString(),
    );
    _maxDestructiveActionsController = TextEditingController(
      text: widget.defaults.maxDestructiveActions.toString(),
    );
    _localOriginalRetentionController = TextEditingController(
      text: widget.defaults.localOriginalRetentionDays.toString(),
    );
    _syncOnWrite = widget.defaults.syncOnWrite;
    _syncOriginals = widget.defaults.syncOriginals;
    _downloadOriginals = widget.defaults.downloadOriginals;
  }

  @override
  void dispose() {
    _remoteFolderController.dispose();
    _minimumIntervalController.dispose();
    _maxDestructiveActionsController.dispose();
    _localOriginalRetentionController.dispose();
    super.dispose();
  }

  Future<void> _disconnect() async {
    final disconnected = await widget.onDisconnect();
    if (disconnected && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _cleanLocalOriginals() async {
    if (_isCleaningOriginals) {
      return;
    }
    final retentionDays =
        int.tryParse(_localOriginalRetentionController.text.trim()) ??
        widget.defaults.localOriginalRetentionDays;
    setState(() {
      _isCleaningOriginals = true;
    });
    try {
      final result = await widget.onCleanLocalOriginals(
        Duration(days: retentionDays < 1 ? 1 : retentionDays),
      );
      if (!mounted) {
        return;
      }
      final freedMb = (result.freedBytes / (1024 * 1024)).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已清理 ${result.deletedOriginals} 张本地原图，释放 $freedMb MB'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCleaningOriginals = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OneDrive 设置'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: DiaryPage(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DiaryHero(
              eyebrow: '同步设置',
              title: '控制 OneDrive 同步',
              subtitle: '默认只手动同步。自动同步需要明确打开，并且会受最小间隔和删除保护限制。',
            ),
            const SizedBox(height: 20),
            DiaryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _remoteFolderController,
                    decoration: const InputDecoration(
                      labelText: '远端目录',
                      hintText: '默认 love_diary',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '两台设备必须使用同一个目录名。目录切换后，建议先手动同步一次。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: DiaryPalette.wine),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    value: _syncOnWrite,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('写入后自动同步'),
                    subtitle: const Text(
                      '开启后，发布、评论和删除会自动同步；同步进行时应用保持可浏览，但写入入口会暂时只读。',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _syncOnWrite = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minimumIntervalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '自动同步最小间隔（分钟）',
                      hintText: '默认 0，表示每次写入都同步',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _maxDestructiveActionsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '删除保护阈值',
                      hintText: '默认 3',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '一次同步里的删除动作超过这个数量时会被拦截，避免误删扩散到云端。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: DiaryPalette.wine),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            DiaryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    value: _syncOriginals,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同步原图到 OneDrive'),
                    subtitle: const Text('关闭时只同步缩略图和预览图，旧原图会留在本机。'),
                    onChanged: (value) {
                      setState(() {
                        _syncOriginals = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    value: _downloadOriginals,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('从 OneDrive 下载原图'),
                    subtitle: const Text('关闭时新设备不会主动拉取云端原图。'),
                    onChanged: (value) {
                      setState(() {
                        _downloadOriginals = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _localOriginalRetentionController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '本地原图保留天数',
                      hintText: '默认 30',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isCleaningOriginals
                        ? null
                        : _cleanLocalOriginals,
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: Text(_isCleaningOriginals ? '正在清理...' : '清理过期本地原图'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () {
                    final remoteFolder =
                        _remoteFolderController.text.trim().isEmpty
                        ? 'love_diary'
                        : _remoteFolderController.text.trim();
                    final minimumInterval =
                        int.tryParse(_minimumIntervalController.text.trim()) ??
                        10;
                    final maxDestructiveActions =
                        int.tryParse(
                          _maxDestructiveActionsController.text.trim(),
                        ) ??
                        3;
                    final localOriginalRetentionDays =
                        int.tryParse(
                          _localOriginalRetentionController.text.trim(),
                        ) ??
                        30;
                    Navigator.of(context).pop(
                      _OneDriveConfigFormData(
                        remoteFolder: remoteFolder,
                        syncOnWrite: _syncOnWrite,
                        minimumSyncIntervalMinutes: minimumInterval < 1
                            ? 1
                            : minimumInterval,
                        maxDestructiveActions: maxDestructiveActions < 0
                            ? 0
                            : maxDestructiveActions,
                        syncOriginals: _syncOriginals,
                        downloadOriginals: _downloadOriginals,
                        localOriginalRetentionDays:
                            localOriginalRetentionDays < 1
                            ? 1
                            : localOriginalRetentionDays,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
                OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('断开连接'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
