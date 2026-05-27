import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'ui/real_home_flow_page.dart';
import 'ui/real_us_tab.dart';
import 'ui/sync_conflict_page.dart';

part 'ui/shell/love_daily_shell_chrome.dart';
part 'ui/schedules/schedule_pages.dart';
part 'ui/dustbin/dustbin_page.dart';
part 'ui/profile/profile_setup_page.dart';
part 'ui/entries/entry_pages.dart';
part 'ui/attachments/attachment_widgets.dart';
part 'ui/settings/onedrive_sync_settings_page.dart';

const List<String> kDiaryMoods = [
  '开心',
  '安心',
  '温柔',
  '想念',
  '真诚',
  '治愈',
  '甜',
  '难过',
  '委屈',
  '生气',
  '焦虑',
  '孤独',
  '失落',
];

class LoveDailyApp extends StatelessWidget {
  const LoveDailyApp({super.key, this.storage});

  final DiaryStorage? storage;

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
      home: LoveDailyShell(storage: storage ?? DiaryStorage()),
    );
  }
}

class StartupTransitionPage extends StatefulWidget {
  const StartupTransitionPage({super.key});

  @override
  State<StartupTransitionPage> createState() => _StartupTransitionPageState();
}

class _StartupTransitionPageState extends State<StartupTransitionPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: DiaryBackground()),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.96 + value * 0.04,
                    child: child,
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final pulse = reduceMotion
                          ? 0.0
                          : math.sin(_controller.value * math.pi) * 0.035;
                      return Transform.scale(scale: 1 + pulse, child: child);
                    },
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        color: DiaryPalette.white.withValues(alpha: 0.84),
                        shape: BoxShape.circle,
                        border: Border.all(color: DiaryPalette.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: DiaryPalette.rose.withValues(alpha: 0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.auto_stories_rounded,
                        size: 42,
                        color: DiaryPalette.rose,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '恋爱日记',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: DiaryPalette.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '把今天轻轻放好',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DiaryPalette.wine,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoveDailyShell extends StatefulWidget {
  const LoveDailyShell({super.key, this.storage});

  final DiaryStorage? storage;

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
  static const Duration _foregroundUpdateInterval = Duration(milliseconds: 350);
  static const double _immersiveTopBarReservedHeight = 72;

  late final DiaryStorage _storage = widget.storage ?? DiaryStorage();
  late final String _startupQuote = randomDailyQuote();
  final ValueNotifier<bool> _writeLockedListenable = ValueNotifier(false);
  final ValueNotifier<int> _syncStatusRevision = ValueNotifier(0);
  final GlobalKey<RealHomeFlowPageState> _homeFlowKey =
      GlobalKey<RealHomeFlowPageState>();
  List<DiaryEntry> _entries = const [];
  CoupleProfile _profile = DiaryStorage.seedProfile();
  bool _isLoaded = false;
  bool _isConnectingOneDrive = false;
  bool _isSyncingOneDrive = false;
  bool _isCancellingOneDriveSync = false;
  bool _hasCheckedStartupOneDriveSync = false;
  bool _startupRestoreRequested = false;
  bool _isTimelineBarVisible = false;
  DateTime? _lastSyncedAt;
  DateTime? _lastSyncFailedAt;
  String? _lastSyncFailureMessage;
  DateTime? _syncStartedAt;
  double? _oneDriveSyncProgress;
  String? _oneDriveSyncLabel;
  final List<_SyncStatusEntry> _syncStatusHistory = [];
  DateTime? _lastForegroundUpdateAt;
  String? _syncCancellationReason;
  bool _isActionMenuOpen = false;
  OneDriveSyncConfig? _oneDriveConfig;
  List<ScheduleItem> _schedules = const [];
  String? _storageRootPath;
  String? _startupLoadError;

  // 页面缓存

  @override
  void initState() {
    super.initState();
    _loadAppData();
  }

  @override
  void dispose() {
    _writeLockedListenable.dispose();
    _syncStatusRevision.dispose();
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
    final normalizedProgress = progress.clamp(0, 1).toDouble();
    _oneDriveSyncProgress = normalizedProgress;
    _oneDriveSyncLabel = label;
    if (_syncStatusHistory.isEmpty ||
        _syncStatusHistory.last.label != label ||
        (_syncStatusHistory.last.progress - normalizedProgress).abs() > 0.001) {
      _syncStatusHistory.add(
        _SyncStatusEntry(
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

  List<_SyncStatusEntry> _currentSyncStatusHistory() {
    final history = List<_SyncStatusEntry>.from(_syncStatusHistory.reversed);
    final currentLabel = _oneDriveSyncLabel;
    if (history.isEmpty && currentLabel != null) {
      history.add(
        _SyncStatusEntry(
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

  void _cancelOneDriveSync() {
    if (!_isSyncingOneDrive || _isCancellingOneDriveSync || !mounted) {
      return;
    }
    setState(() {
      _isCancellingOneDriveSync = true;
      _syncCancellationReason = 'OneDrive 同步已取消。';
      _recordSyncStatus(_oneDriveSyncProgress ?? 0, '已请求取消：正在等待当前网络步骤安全结束');
    });
    unawaited(
      _updateForegroundSyncStatus(
        label: '正在取消 OneDrive 同步…',
        progress: _oneDriveSyncProgress,
        force: true,
      ),
    );
  }

  void _closeActionMenu() {
    if (!_isActionMenuOpen || !mounted) {
      return;
    }
    setState(() {
      _isActionMenuOpen = false;
    });
  }

  Future<void> _loadAppData() async {
    var currentStep = 'loadData';
    String? resolvedRootPath;
    try {
      final results = await Future.wait([
        _storage.loadEntries(),
        _storage.loadProfile(),
        _storage.loadSchedules(),
        _storage.resolveRootDirectory(),
      ]);

      final entries = results[0] as List<DiaryEntry>;
      final profile = results[1] as CoupleProfile;
      final schedules = results[2] as List<ScheduleItem>;
      final rootDirectory = results[3] as Directory;
      resolvedRootPath = rootDirectory.path;

      currentStep = 'loadSyncState';
      final syncResults = await Future.wait([
        _storage.loadSyncState(SyncProvider.oneDrive),
        _storage.loadOneDriveSyncConfig(),
      ]);
      final syncState = syncResults[0] as SyncState;
      final oneDriveConfig = syncResults[1] as OneDriveSyncConfig?;

      if (!mounted) {
        return;
      }

      setState(() {
        _entries = entries;
        _profile = profile;
        _schedules = schedules;
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
        _schedules = const [];
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

  Future<void> _persistProfile() => _storage.saveProfile(_profile);

  Future<void> _reloadEntries() async {
    final entries = await _storage.loadEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
    });
  }

  Future<void> _reloadSchedules() async {
    final schedules = await _storage.loadSchedules();
    if (!mounted) {
      return;
    }
    setState(() {
      _schedules = schedules;
    });
  }

  Future<ScheduleItem?> _openScheduleEditor({
    ScheduleItem? initialSchedule,
    DateTime? initialDate,
  }) async {
    if (!_guardWritableAction()) {
      return null;
    }
    _closeActionMenu();

    final schedule = await Navigator.of(context).push<ScheduleItem>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScheduleEditorPage(
          initialSchedule: initialSchedule,
          initialDate: initialDate,
          writeLockedListenable: _writeLockedListenable,
          onWriteBlocked: _showWriteLockedMessage,
        ),
      ),
    );

    if (schedule == null) {
      return null;
    }

    final savedSchedule = await _storage.saveSchedule(schedule);
    await _reloadSchedules();
    unawaited(
      _triggerAutoSync(reason: initialSchedule == null ? '添加日程' : '更新日程'),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(initialSchedule == null ? '日程已保存' : '日程已更新')),
      );
    }
    return savedSchedule;
  }

  Future<void> _openScheduleManager({DateTime? initialDate}) async {
    _closeActionMenu();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScheduleManagerPage(
          schedules: _schedules,
          initialDate: initialDate,
          writeLockedListenable: _writeLockedListenable,
          onWriteBlocked: _showWriteLockedMessage,
          onSaveSchedule: (schedule) async {
            await _storage.saveSchedule(schedule);
            await _reloadSchedules();
            unawaited(_triggerAutoSync(reason: '保存日程'));
          },
          onDeleteSchedule: (schedule) async {
            await _storage.deleteSchedule(schedule);
            await _reloadSchedules();
            unawaited(_triggerAutoSync(reason: '删除日程'));
          },
        ),
      ),
    );

    if (changed == true) {
      await _reloadSchedules();
    }
  }

  Future<DiaryEntry?> _openEditor({DiaryEntry? initialEntry}) async {
    if (!_guardWritableAction()) {
      return null;
    }

    final entry = await Navigator.of(context).push<DiaryEntry>(
      buildDiaryRoute(
        CreateEntryPage(
          storage: _storage,
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

    final savedEntry = await _storage.saveEntry(entry);
    if (initialEntry == null) {
      await _storage.clearEntryDraft();
    }
    await _reloadEntries();

    if (!mounted) {
      return savedEntry;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final homeFlow = _homeFlowKey.currentState;
        if (homeFlow != null) {
          unawaited(homeFlow.scrollToTimeline());
        }
      }
    });

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
    await _storage.saveEntry(updatedEntry);
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

    await _storage.deleteEntry(entry);
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
      buildDiaryRoute(
        ProfileSetupPage(
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
      buildDiaryRoute(
        DustbinPage(
          storage: _storage,
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
      buildDiaryRoute(
        EntryDetailPage(
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
    return OneDriveAuthService(storage: _storage);
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
    );
    final resetSyncBaseline =
        _oneDriveConfig!.remoteFolder != updated.remoteFolder;
    if (resetSyncBaseline) {
      await _storage.resetSyncState(SyncProvider.oneDrive);
    }
    await _storage.saveOneDriveSyncConfig(updated);
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
      _isCancellingOneDriveSync = false;
      _syncCancellationReason = null;
      _syncStartedAt = DateTime.now();
      _syncStatusHistory.clear();
      _recordSyncStatus(0, initialSyncLabel);
      _lastForegroundUpdateAt = null;
    });

    try {
      await _yieldToUi();
      await SyncForegroundGuard.start(label: initialSyncLabel, progress: 0);
      _lastForegroundUpdateAt = DateTime.now();
      await _yieldToUi();

      final remoteSource = _oneDriveRemoteSource();
      final executor = DiarySyncExecutor(
        storage: _storage,
        remoteSource: remoteSource,
        provider: SyncProvider.oneDrive,
        safetyPolicy: SyncSafetyPolicy(
          maxDestructiveActions: _oneDriveConfig!.maxDestructiveActions,
        ),
        attachmentPolicy: const AttachmentSyncPolicy(),
        onProgress: (progress, label) {
          unawaited(
            _updateForegroundSyncStatus(label: label, progress: progress),
          );
          if (!mounted) {
            return;
          }
          _recordSyncStatus(progress, label);
        },
        checkCancelled: _checkSyncCancelled,
      );
      final result = await executor.sync();
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
          conflictDetails: result.conflictDetails,
          remoteSource: remoteSource,
          provider: SyncProvider.oneDrive,
          attachmentPolicy: const AttachmentSyncPolicy(),
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
    } on SyncCancelledException catch (error) {
      final message = error.message;
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
          _isCancellingOneDriveSync = false;
          _syncCancellationReason = null;
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
    if (config == null) {
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
    final currentState = await _storage.loadSyncState(provider);
    final failedState = currentState.copyWith(
      lastFailedAt: DateTime.now(),
      lastFailureMessage: message,
    );
    await _storage.saveSyncState(failedState, provider);
    if (provider == SyncProvider.oneDrive && mounted) {
      setState(() {
        _lastSyncFailedAt = failedState.lastFailedAt;
        _lastSyncFailureMessage = failedState.lastFailureMessage;
      });
    }
  }

  Future<void> _handleSyncConflicts({
    required List<String> conflictPaths,
    required List<SyncConflictDetail> conflictDetails,
    required DiarySyncRemoteSource remoteSource,
    required SyncProvider provider,
    AttachmentSyncPolicy attachmentPolicy = const AttachmentSyncPolicy(),
    required void Function(bool value) setSyncing,
  }) async {
    final result = await Navigator.of(context)
        .push<SyncConflictResolutionResult>(
          MaterialPageRoute(
            builder: (_) => SyncConflictPage(
              conflictPaths: conflictPaths,
              conflictDetails: conflictDetails,
            ),
          ),
        );

    if (result == null || !mounted) {
      return;
    }

    setSyncing(true);

    try {
      final executor = DiarySyncExecutor(
        storage: _storage,
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
    if (_oneDriveConfig == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openUsSheet();
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
      _lastForegroundUpdateAt = null;
    });

    try {
      await _yieldToUi();
      await SyncForegroundGuard.start(label: initialRestoreLabel, progress: 0);
      _lastForegroundUpdateAt = DateTime.now();
      await _yieldToUi();
      final remoteSource = _oneDriveRemoteSource();
      final snapshot = await remoteSource.fetchSnapshot(
        baseline: await _storage.loadSyncState(SyncProvider.oneDrive),
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
      const attachmentPolicy = AttachmentSyncPolicy();
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
        final targetAbsolutePath = await _storage.resolveSyncFileAbsolutePath(
          file.relativePath,
        );
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

      final localFiles = (await _storage.listSyncFiles())
          .where((file) => attachmentPolicy.includeLocalPath(file.relativePath))
          .toList();
      await _storage.saveSyncState(
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
        ),
      ),
    );
  }

  Future<void> _openUsSheet() async {
    _closeActionMenu();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: DiaryPalette.ink.withValues(alpha: 0.24),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          alignment: Alignment.bottomCenter,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: DiaryPalette.paper),
              child: RealUsTab(
                profile: _profile,
                entries: _entries,
                oneDriveConfig: _oneDriveConfig,
                lastSyncedAt: _lastSyncedAt,
                lastSyncFailedAt: _lastSyncFailedAt,
                lastSyncFailureMessage: _lastSyncFailureMessage,
                topContentInset: 0,
                sheetMode: true,
                onEditProfile: () {
                  Navigator.of(sheetContext).pop();
                  _openProfileEditor(firstSetup: false);
                },
                onOpenDustbin: () async {
                  Navigator.of(sheetContext).pop();
                  await _openDustbin();
                },
                onConnectOneDrive: () async {
                  Navigator.of(sheetContext).pop();
                  await _connectOneDrive();
                },
                onOpenOneDriveSettings: () async {
                  Navigator.of(sheetContext).pop();
                  await _openOneDriveSettings();
                },
              ),
            ),
          ),
        );
      },
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StreamBuilder<int>(
          stream: Stream.periodic(const Duration(seconds: 1), (value) => value),
          builder: (context, _) {
            return ValueListenableBuilder<int>(
              valueListenable: _syncStatusRevision,
              builder: (context, _, _) {
                final startedAt = _syncStartedAt;
                final history = _currentSyncStatusHistory();
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
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: DiaryPalette.ink,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          elapsed == null
                              ? 'OneDrive 同步记录'
                              : _isCancellingOneDriveSync
                              ? '已运行 ${elapsed}s，正在取消，同步会在安全节点结束'
                              : '已运行 ${elapsed}s，当前只锁定写入操作',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: DiaryPalette.wine),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            DiaryBadge(
                              label: _isCancellingOneDriveSync
                                  ? '取消中'
                                  : (_isSyncingOneDrive ? '同步中' : '空闲'),
                              tone: _isCancellingOneDriveSync
                                  ? DiaryBadgeTone.rose
                                  : DiaryBadgeTone.ink,
                            ),
                            if (_oneDriveSyncProgress != null)
                              DiaryBadge(
                                label:
                                    '${(_oneDriveSyncProgress!.clamp(0, 1) * 100).round()}%',
                                tone: DiaryBadgeTone.rose,
                              ),
                            DiaryBadge(
                              label: '步骤 ${history.length}',
                              tone: DiaryBadgeTone.sand,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_isSyncingOneDrive) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isCancellingOneDriveSync
                                  ? null
                                  : _cancelOneDriveSync,
                              icon: Icon(
                                _isCancellingOneDriveSync
                                    ? Icons.hourglass_top_rounded
                                    : Icons.stop_circle_outlined,
                              ),
                              label: Text(
                                _isCancellingOneDriveSync ? '正在取消…' : '取消同步',
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: history.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 18),
                            itemBuilder: (context, index) {
                              final item = history[index];
                              final percent = (item.progress.clamp(0, 1) * 100)
                                  .round();
                              final elapsedSeconds = startedAt == null
                                  ? null
                                  : item.recordedAt
                                        .difference(startedAt)
                                        .inSeconds;
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.label,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
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
                                                  color: DiaryPalette.wine
                                                      .withValues(alpha: 0.68),
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
          },
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
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DiaryPalette.white.withValues(
                alpha: DiaryPalette.surfaceStrongAlpha,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: DiaryPalette.white.withValues(
                  alpha: DiaryPalette.surfaceBorderAlpha,
                ),
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
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
                      DiaryBadge(
                        label: _isCancellingOneDriveSync ? '取消中' : '只读中',
                        tone: _isCancellingOneDriveSync
                            ? DiaryBadgeTone.rose
                            : DiaryBadgeTone.ink,
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  LinearProgressIndicator(value: _oneDriveSyncProgress),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (_syncStartedAt != null)
                        Text(
                          '已运行 ${DateTime.now().difference(_syncStartedAt!).inSeconds}s',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: DiaryPalette.wine),
                        ),
                      const Spacer(),
                      if (_isSyncingOneDrive)
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
                          onPressed: _isCancellingOneDriveSync
                              ? null
                              : _cancelOneDriveSync,
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 18,
                          ),
                          label: const Text('取消'),
                        ),
                      const SizedBox(width: 10),
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

  Widget _buildFloatingActionButton() {
    final isSyncBusy = _isConnectingOneDrive || _isSyncingOneDrive;
    final isWriteLocked = _isWriteLocked;
    final hasOneDrive = _oneDriveConfig != null;
    Widget buildAction({
      required VoidCallback? onPressed,
      required IconData icon,
      required String label,
    }) {
      return _isActionMenuOpen
          ? _GlassActionPill(
              key: ValueKey<String>(label),
              icon: icon,
              label: label,
              onPressed: onPressed,
            )
          : const SizedBox.shrink();
    }

    Widget buildActionSwitcher(Widget child, Duration duration) {
      return AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.18),
                end: Offset.zero,
              ).animate(animation),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                child: child,
              ),
            ),
          );
        },
        child: child,
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 8,
        right: 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          buildActionSwitcher(
            buildAction(
              onPressed: () {
                _closeActionMenu();
                unawaited(_openUsSheet());
              },
              icon: Icons.people_alt_rounded,
              label: '我们设置',
            ),
            const Duration(milliseconds: 260),
          ),
          if (_isActionMenuOpen) const SizedBox(height: 10),
          buildActionSwitcher(
            buildAction(
              onPressed: isWriteLocked
                  ? _showWriteLockedMessage
                  : () => unawaited(_openScheduleEditor()),
              icon: Icons.event_note_rounded,
              label: '添加日程',
            ),
            const Duration(milliseconds: 240),
          ),
          if (_isActionMenuOpen) const SizedBox(height: 10),
          buildActionSwitcher(
            buildAction(
              onPressed: isSyncBusy
                  ? null
                  : hasOneDrive
                  ? () {
                      _closeActionMenu();
                      unawaited(_syncWithOneDrive());
                    }
                  : () {
                      _closeActionMenu();
                      _connectOneDrive();
                    },
              icon: hasOneDrive ? Icons.sync_rounded : Icons.cloud_sync_rounded,
              label: _isSyncingOneDrive
                  ? '同步进行'
                  : hasOneDrive
                  ? '同步云端'
                  : '连接云端',
            ),
            const Duration(milliseconds: 220),
          ),
          if (_isActionMenuOpen) const SizedBox(height: 10),
          buildActionSwitcher(
            buildAction(
              onPressed: isWriteLocked
                  ? _showWriteLockedMessage
                  : () {
                      _closeActionMenu();
                      _openEditor();
                    },
              icon: isWriteLocked
                  ? Icons.visibility_rounded
                  : Icons.edit_note_rounded,
              label: isWriteLocked ? '只读查看' : '写篇日记',
            ),
            const Duration(milliseconds: 220),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: _isActionMenuOpen ? 12 : 0,
          ),
          _GlassPlusButton(
            isOpen: _isActionMenuOpen,
            onPressed: () {
              setState(() {
                _isActionMenuOpen = !_isActionMenuOpen;
              });
            },
          ),
        ],
      ),
    );
  }

  double get _topStatusInset {
    var inset = 0.0;
    if (_startupLoadError != null) {
      inset += _immersiveTopBarReservedHeight;
    }
    if (_startupLoadError != null) {
      inset += 112;
    }
    return inset;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const StartupTransitionPage();
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

    final topInset = MediaQuery.paddingOf(context).top;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final homeFlow = RealHomeFlowPage(
      key: _homeFlowKey,
      profile: _profile,
      entries: _entries,
      schedules: _schedules,
      startupQuote: _startupQuote,
      rootDirectoryPath: _storageRootPath,
      isWriteLocked: _isWriteLocked,
      topContentInset: _topStatusInset,
      onWriteBlocked: _showWriteLockedMessage,
      onOpenSchedules: (date) => _openScheduleManager(initialDate: date),
      onOpenEntry: _openEntryDetail,
      onEditEntry: _editEntry,
      onDeleteEntry: _deleteEntry,
      syncStatusRevision: _syncStatusRevision,
      isSyncingOneDrive: _isSyncingOneDrive,
      isCancellingOneDriveSync: _isCancellingOneDriveSync,
      oneDriveSyncProgress: _oneDriveSyncProgress,
      oneDriveSyncLabel: _oneDriveSyncLabel,
      onShowSyncDetails: _showSyncStatusDetails,
      onTimelineBarVisibilityChanged: (visible) {
        if (_isTimelineBarVisible == visible || !mounted) {
          return;
        }
        setState(() {
          _isTimelineBarVisible = visible;
        });
      },
    );

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const Positioned.fill(child: DiaryBackground()),
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 18),
                    child: child,
                  ),
                );
              },
              child: homeFlow,
            ),
          ),
          if (_isActionMenuOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeActionMenu,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top:
                topInset +
                (_startupLoadError == null
                    ? 10
                    : _immersiveTopBarReservedHeight),
            child: IgnorePointer(
              ignoring:
                  (!_isSyncingOneDrive || _isTimelineBarVisible) &&
                  _startupLoadError == null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStartupErrorBanner(),
                  if (!_isTimelineBarVisible) _buildSyncStatusBanner(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }
}
