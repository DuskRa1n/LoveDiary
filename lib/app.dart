import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/diary_storage.dart';
import 'models/diary_models.dart';
import 'sync/diary_sync_executor.dart';
import 'sync/onedrive/onedrive_auth_service.dart';
import 'sync/onedrive/onedrive_models.dart';
import 'sync/sync_models.dart';
import 'sync/sync_remote_source.dart';
import 'sync/sync_controller.dart';
import 'ui/diary_design.dart';
import 'ui/daily_quotes.dart';
import 'ui/real_home_flow_page.dart';
import 'ui/real_us_tab.dart';
import 'ui/sync_conflict_page.dart';

import 'ui/dustbin/dustbin_page.dart';
import 'ui/entries/entry_pages.dart';
import 'ui/profile/profile_setup_page.dart';
import 'ui/schedules/schedule_pages.dart';
import 'ui/settings/onedrive_sync_settings_page.dart';
import 'ui/shell/love_daily_shell_chrome.dart';
import 'utils/app_log.dart';
import 'utils/background_task.dart';

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
        textTheme: ThemeData.light().textTheme
            .apply(bodyColor: DiaryPalette.ink, displayColor: DiaryPalette.ink)
            .copyWith(
              headlineLarge: ThemeData.light().textTheme.headlineLarge
                  ?.copyWith(fontFamily: 'Noto Serif SC'),
              headlineMedium: ThemeData.light().textTheme.headlineMedium
                  ?.copyWith(fontFamily: 'Noto Serif SC'),
              headlineSmall: ThemeData.light().textTheme.headlineSmall
                  ?.copyWith(fontFamily: 'Noto Serif SC'),
              titleLarge: ThemeData.light().textTheme.titleLarge?.copyWith(
                fontFamily: 'Noto Serif SC',
              ),
              titleMedium: ThemeData.light().textTheme.titleMedium?.copyWith(
                fontFamily: 'Noto Serif SC',
              ),
              titleSmall: ThemeData.light().textTheme.titleSmall?.copyWith(
                fontFamily: 'Noto Serif SC',
              ),
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

enum _UsSheetAction {
  editProfile,
  openDustbin,
  connectOneDrive,
  openOneDriveSettings,
  runMaintenance,
  openDiagnostics,
}

class LoveDailyShell extends StatefulWidget {
  const LoveDailyShell({super.key, this.storage});

  final DiaryStorage? storage;

  @override
  State<LoveDailyShell> createState() => _LoveDailyShellState();
}

class _LoveDailyShellState extends State<LoveDailyShell> {
  static const double _immersiveTopBarReservedHeight = 72;

  late final DiaryStorage _storage = widget.storage ?? DiaryStorage();
  late final String _startupQuote = randomDailyQuote();
  late final SyncController _sync = SyncController(
    storage: _storage,
    onShowMessage: _showMessage,
  );
  final GlobalKey<RealHomeFlowPageState> _homeFlowKey =
      GlobalKey<RealHomeFlowPageState>();
  List<DiaryEntry> _entries = const [];
  CoupleProfile _profile = DiaryStorage.seedProfile();
  bool _isLoaded = false;
  bool _isTimelineBarVisible = false;
  bool _isActionMenuOpen = false;
  List<ScheduleItem> _schedules = const [];
  String? _storageRootPath;
  String? _startupLoadError;
  bool _isRunningMaintenance = false;

  @override
  void initState() {
    super.initState();
    _sync.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAppData();
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  void _closeActionMenu() {
    if (!_isActionMenuOpen || !mounted) {
      return;
    }
    setState(() {
      _isActionMenuOpen = false;
    });
  }

  Future<void> _loadAppData({bool runMaintenance = true}) async {
    var currentStep = 'loadData';
    String? resolvedRootPath;
    try {
      if (runMaintenance) {
        currentStep = 'selfMaintenance';
        try {
          final result = await _storage.runSelfMaintenance();
          if (result.changed) {
            AppLog.info(
              '自维护完成：临时文件 ${result.deletedTemporaryFiles}，回收站 ${result.purgedDustbinEntries}，同步状态 ${result.repairedSyncStates}',
            );
          }
        } catch (error, stackTrace) {
          AppLog.error('启动自维护失败', error, stackTrace);
        }
      }

      currentStep = 'loadData';
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
        _storageRootPath = rootDirectory.path;
        _startupLoadError = null;
        _isLoaded = true;
      });

      final shouldSync = _sync.applyLoadedState(
        syncState: syncState,
        config: oneDriveConfig,
      );

      if (shouldSync) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaitedLogged('Startup OneDrive sync failed', () async {
              await _sync.syncWithOneDrive(
                interactive: false,
                loadAppData: _loadAppData,
                showResultDialog: _showSyncResultDialog,
                handleSyncConflicts: _handleSyncConflicts,
              );
            });
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

      _sync.resetSyncState();

      setState(() {
        _entries = const [];
        _profile = DiaryStorage.seedProfile();
        _schedules = const [];
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

  void _triggerAutoSyncInBackground(String reason) {
    unawaitedLogged(
      'Auto sync failed: $reason',
      () => _sync.triggerAutoSync(
        reason: reason,
        loadAppData: _loadAppData,
        showResultDialog: _showSyncResultDialog,
        handleSyncConflicts: _handleSyncConflicts,
      ),
    );
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
    if (!_sync.guardWritableAction()) {
      return null;
    }
    _closeActionMenu();

    final schedule = await Navigator.of(context).push<ScheduleItem>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScheduleEditorPage(
          initialSchedule: initialSchedule,
          initialDate: initialDate,
          writeLockedListenable: _sync.writeLockedListenable,
          onWriteBlocked: _sync.showWriteLockedMessage,
        ),
      ),
    );

    if (schedule == null) {
      return null;
    }

    final savedSchedule = await _storage.saveSchedule(schedule);
    await _reloadSchedules();
    _triggerAutoSyncInBackground(initialSchedule == null ? '添加日程' : '更新日程');

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
          writeLockedListenable: _sync.writeLockedListenable,
          onWriteBlocked: _sync.showWriteLockedMessage,
          onSaveSchedule: (schedule) async {
            await _storage.saveSchedule(schedule);
            await _reloadSchedules();
            _triggerAutoSyncInBackground('保存日程');
          },
          onDeleteSchedule: (schedule) async {
            await _storage.deleteSchedule(schedule);
            await _reloadSchedules();
            _triggerAutoSyncInBackground('删除日程');
          },
        ),
      ),
    );

    if (changed == true) {
      await _reloadSchedules();
    }
  }

  Future<DiaryEntry?> _openEditor({DiaryEntry? initialEntry}) async {
    if (!_sync.guardWritableAction()) {
      return null;
    }

    final entry = await Navigator.of(context).push<DiaryEntry>(
      buildDiaryRoute(
        CreateEntryPage(
          profile: _profile,
          initialEntry: initialEntry,
          rootDirectoryPath: _storageRootPath,
          writeLockedListenable: _sync.writeLockedListenable,
          onWriteBlocked: _sync.showWriteLockedMessage,
          onLoadDraft: () => _storage.loadEntryDraft(),
          onSaveDraft: (draft) => _storage.saveEntryDraft(draft),
          onClearDraft: () => _storage.clearEntryDraft(),
          onImportAttachment:
              ({
                required sourcePath,
                required fileName,
                required keepOriginal,
              }) => _storage.importAttachment(
                sourcePath: sourcePath,
                fileName: fileName,
                keepOriginal: keepOriginal,
              ),
          onDeleteAttachments: (attachments) =>
              _storage.deleteAttachments(attachments),
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
          unawaitedLogged(
            'Scroll timeline after saving entry failed',
            homeFlow.scrollToTimeline,
          );
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
    _triggerAutoSyncInBackground(initialEntry == null ? '发布日记' : '更新日记');
    return savedEntry;
  }

  Future<DiaryEntry> _addComment(String entryId, DiaryComment comment) async {
    if (!_sync.guardWritableAction()) {
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
    _triggerAutoSyncInBackground('发表评论');
    return updatedEntry;
  }

  Future<DiaryEntry?> _editEntry(DiaryEntry entry) {
    return _openEditor(initialEntry: entry);
  }

  Future<void> _deleteEntry(DiaryEntry entry) async {
    if (!_sync.guardWritableAction()) {
      return;
    }

    await _storage.deleteEntry(entry);
    await _reloadEntries();
    _triggerAutoSyncInBackground('删除日记');

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除《${entry.title}》')));
  }

  void _openEntryDetail(DiaryEntry entry) {
    Navigator.of(context).push(
      buildDiaryRoute(
        EntryDetailPage(
          profile: _profile,
          entry: entry,
          rootDirectoryPath: _storageRootPath,
          writeLockedListenable: _sync.writeLockedListenable,
          onWriteBlocked: _sync.showWriteLockedMessage,
          onAddComment: _addComment,
          onEditEntry: _editEntry,
          onDeleteEntry: _deleteEntry,
        ),
      ),
    );
  }

  Future<void> _handleSyncConflicts({
    required List<String> conflictPaths,
    required List<SyncConflictDetail> conflictDetails,
    required DiarySyncRemoteSource remoteSource,
    required SyncProvider provider,
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
        attachmentPolicy: const AttachmentSyncPolicy(),
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
      await _sync.recordSyncFailure(SyncProvider.oneDrive, error.message);
      _showMessage(error.message);
    } catch (error) {
      await _sync.recordSyncFailure(SyncProvider.oneDrive, '处理冲突失败：$error');
      _showMessage('处理冲突失败：$error');
    } finally {
      setSyncing(false);
    }
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
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
    return confirmed == true;
  }

  Future<void> _openProfileSettings() async {
    final updatedProfile = await Navigator.of(context).push<CoupleProfile>(
      buildDiaryRoute(
        ProfileSetupPage(
          initialProfile: _profile,
          isFirstSetup: false,
          writeLockedListenable: _sync.writeLockedListenable,
          onWriteBlocked: _sync.showWriteLockedMessage,
        ),
      ),
    );
    if (updatedProfile == null || !mounted) {
      return;
    }

    setState(() {
      _profile = updatedProfile;
    });
    await _persistProfile();
    _showMessage('关系信息已保存');
    _triggerAutoSyncInBackground('更新关系信息');
  }

  Future<void> _openDustbinPage() async {
    final changed = await Navigator.of(context).push<bool>(
      buildDiaryRoute(
        DustbinPage(
          storage: _storage,
          writeLockedListenable: _sync.writeLockedListenable,
          onWriteBlocked: _sync.showWriteLockedMessage,
        ),
      ),
    );
    if (changed == true) {
      await _reloadEntries();
    }
  }

  Future<void> _openOneDriveSettingsPage() async {
    final currentConfig = _sync.oneDriveConfig;
    if (currentConfig == null) {
      await _sync.connectOneDrive(
        showPage: <T>(Route<T> page) => Navigator.of(context).push<T>(page),
        loadAppData: _loadAppData,
        openUsSheet: _openUsSheet,
      );
      return;
    }

    final formData = await Navigator.of(context).push<OneDriveConfigFormData>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) {
          final defaults = OneDriveConfigFormData(
            remoteFolder: currentConfig.remoteFolder,
            syncOnWrite: currentConfig.syncOnWrite,
            minimumSyncIntervalMinutes:
                currentConfig.minimumSyncIntervalMinutes,
            maxDestructiveActions: currentConfig.maxDestructiveActions,
          );
          return OneDriveSyncSettingsPage(
            defaults: defaults,
            onDisconnect: () =>
                _sync.disconnectOneDrive(showConfirm: _showConfirmDialog),
          );
        },
      ),
    );

    if (formData == null || !mounted) {
      return;
    }

    final latestConfig = _sync.oneDriveConfig;
    if (latestConfig == null) {
      return;
    }
    final updated = latestConfig.copyWith(
      remoteFolder: formData.remoteFolder,
      syncOnWrite: formData.syncOnWrite,
      minimumSyncIntervalMinutes: formData.minimumSyncIntervalMinutes,
      maxDestructiveActions: formData.maxDestructiveActions,
    );
    final resetSyncBaseline = latestConfig.remoteFolder != updated.remoteFolder;
    await _sync.updateOneDriveConfig(
      updated: updated,
      resetSyncBaseline: resetSyncBaseline,
    );
    _showMessage('OneDrive 同步设置已保存');
  }

  Future<void> _runSelfMaintenance() async {
    if (_isRunningMaintenance) {
      return;
    }
    if (_sync.isSyncingOneDrive) {
      _showMessage('正在同步中，完成后再执行自检维护。');
      return;
    }

    setState(() {
      _isRunningMaintenance = true;
    });
    try {
      final result = await _storage.runSelfMaintenance();
      await _loadAppData(runMaintenance: false);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('自检维护完成'),
            content: Text(_selfMaintenanceSummary(result)),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ],
          );
        },
      );
    } catch (error, stackTrace) {
      AppLog.error('手动自维护失败', error, stackTrace);
      if (mounted) {
        _showMessage('自检维护失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRunningMaintenance = false;
        });
      }
    }
  }

  String _selfMaintenanceSummary(AppSelfMaintenanceResult result) {
    final buffer = StringBuffer()
      ..writeln('已重建 ${result.indexedEntries} 篇日记索引。')
      ..writeln('清理临时文件：${result.deletedTemporaryFiles} 个')
      ..writeln('清理过期回收站：${result.purgedDustbinEntries} 篇')
      ..writeln('修复同步状态：${result.repairedSyncStates} 项');
    if (!result.changed) {
      buffer.writeln();
      buffer.write('没有发现需要自动修复的问题。');
    }
    return buffer.toString();
  }

  Future<void> _openUsSheet() async {
    _closeActionMenu();
    final action = await showModalBottomSheet<_UsSheetAction>(
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
                oneDriveConfig: _sync.oneDriveConfig,
                lastSyncedAt: _sync.lastSyncedAt,
                lastSyncFailedAt: _sync.lastSyncFailedAt,
                lastSyncFailureMessage: _sync.lastSyncFailureMessage,
                topContentInset: 0,
                sheetMode: true,
                onEditProfile: () {
                  Navigator.of(sheetContext).pop(_UsSheetAction.editProfile);
                },
                onOpenDustbin: () async {
                  Navigator.of(sheetContext).pop(_UsSheetAction.openDustbin);
                },
                onConnectOneDrive: () async {
                  Navigator.of(
                    sheetContext,
                  ).pop(_UsSheetAction.connectOneDrive);
                },
                onOpenOneDriveSettings: () async {
                  Navigator.of(
                    sheetContext,
                  ).pop(_UsSheetAction.openOneDriveSettings);
                },
                onRunMaintenance: () async {
                  Navigator.of(sheetContext).pop(_UsSheetAction.runMaintenance);
                },
                onOpenDiagnostics: () async {
                  Navigator.of(
                    sheetContext,
                  ).pop(_UsSheetAction.openDiagnostics);
                },
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _UsSheetAction.editProfile:
        await _openProfileSettings();
        break;
      case _UsSheetAction.openDustbin:
        await _openDustbinPage();
        break;
      case _UsSheetAction.connectOneDrive:
        await _sync.connectOneDrive(
          showPage: <T>(Route<T> page) => Navigator.of(context).push<T>(page),
          loadAppData: _loadAppData,
          openUsSheet: _openUsSheet,
        );
        break;
      case _UsSheetAction.openOneDriveSettings:
        await _openOneDriveSettingsPage();
        break;
      case _UsSheetAction.runMaintenance:
        await _runSelfMaintenance();
        break;
      case _UsSheetAction.openDiagnostics:
        await _showDiagnosticsDialog();
        break;
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDiagnosticsDialog() async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var diagnosticText = AppLog.diagnosticText();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('诊断日志'),
              content: SizedBox(
                width: double.maxFinite,
                height: 360,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: DiaryPalette.mist.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      diagnosticText,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    AppLog.clearDiagnostics();
                    setDialogState(() {
                      diagnosticText = AppLog.diagnosticText();
                    });
                  },
                  child: const Text('清空'),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: diagnosticText),
                    );
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(const SnackBar(content: Text('诊断日志已复制')));
                    }
                  },
                  child: const Text('复制'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
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
              valueListenable: _sync.syncStatusRevision,
              builder: (context, _, _) {
                final startedAt = _sync.syncStartedAt;
                final history = _sync.currentSyncStatusHistory();
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
                              : _sync.isCancellingOneDriveSync
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
                              label: _sync.isCancellingOneDriveSync
                                  ? '取消中'
                                  : (_sync.isSyncingOneDrive ? '同步中' : '空闲'),
                              tone: _sync.isCancellingOneDriveSync
                                  ? DiaryBadgeTone.rose
                                  : DiaryBadgeTone.ink,
                            ),
                            if (_sync.oneDriveSyncProgress != null)
                              DiaryBadge(
                                label:
                                    '${(_sync.oneDriveSyncProgress!.clamp(0, 1) * 100).round()}%',
                                tone: DiaryBadgeTone.rose,
                              ),
                            DiaryBadge(
                              label: '步骤 ${history.length}',
                              tone: DiaryBadgeTone.sand,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_sync.isSyncingOneDrive) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _sync.isCancellingOneDriveSync
                                  ? null
                                  : _sync.cancelOneDriveSync,
                              icon: Icon(
                                _sync.isCancellingOneDriveSync
                                    ? Icons.hourglass_top_rounded
                                    : Icons.stop_circle_outlined,
                              ),
                              label: Text(
                                _sync.isCancellingOneDriveSync
                                    ? '正在取消…'
                                    : '取消同步',
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
    if (!_sync.isSyncingOneDrive) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: _sync.syncStatusRevision,
      builder: (context, _, _) {
        final percent = _sync.oneDriveSyncProgress == null
            ? null
            : '${(_sync.oneDriveSyncProgress!.clamp(0, 1) * 100).round()}%';

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
                          _sync.oneDriveSyncLabel ?? 'OneDrive 正在同步',
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
                        label: _sync.isCancellingOneDriveSync ? '取消中' : '只读中',
                        tone: _sync.isCancellingOneDriveSync
                            ? DiaryBadgeTone.rose
                            : DiaryBadgeTone.ink,
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  LinearProgressIndicator(value: _sync.oneDriveSyncProgress),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (_sync.syncStartedAt != null)
                        Text(
                          '已运行 ${DateTime.now().difference(_sync.syncStartedAt!).inSeconds}s',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: DiaryPalette.wine),
                        ),
                      const Spacer(),
                      if (_sync.isSyncingOneDrive)
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
                          onPressed: _sync.isCancellingOneDriveSync
                              ? null
                              : _sync.cancelOneDriveSync,
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
    final isSyncBusy = _sync.isConnectingOneDrive || _sync.isSyncingOneDrive;
    final isWriteLocked = _sync.isWriteLocked;
    final hasOneDrive = _sync.oneDriveConfig != null;
    Widget buildAction({
      required VoidCallback? onPressed,
      required IconData icon,
      required String label,
    }) {
      return _isActionMenuOpen
          ? GlassActionPill(
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
                unawaitedLogged('Open us sheet failed', _openUsSheet);
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
                  ? _sync.showWriteLockedMessage
                  : () => unawaitedLogged(
                      'Open schedule editor failed',
                      () async {
                        await _openScheduleEditor();
                      },
                    ),
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
                      unawaitedLogged('Manual OneDrive sync failed', () async {
                        await _sync.syncWithOneDrive(
                          loadAppData: _loadAppData,
                          showResultDialog: _showSyncResultDialog,
                          handleSyncConflicts: _handleSyncConflicts,
                        );
                      });
                    }
                  : () {
                      _closeActionMenu();
                      _sync.connectOneDrive(
                        showPage: <T>(Route<T> page) =>
                            Navigator.of(context).push<T>(page),
                        loadAppData: _loadAppData,
                        openUsSheet: _openUsSheet,
                      );
                    },
              icon: hasOneDrive ? Icons.sync_rounded : Icons.cloud_sync_rounded,
              label: _sync.isSyncingOneDrive
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
                  ? _sync.showWriteLockedMessage
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
          GlassPlusButton(
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
    if (_sync.isSyncingOneDrive) {
      inset += 112;
    }
    return inset;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const StartupTransitionPage();
    }

    if (!_profile.isOnboarded && !_sync.startupRestoreRequested) {
      return ProfileSetupPage(
        initialProfile: _profile,
        isFirstSetup: true,
        canRestoreFromOneDrive: _shouldOfferStartupRecovery(
          entries: _entries,
          profile: _profile,
        ),
        hasOneDriveConfig: _sync.oneDriveConfig != null,
        onRestoreFromOneDrive: () => _sync.startStartupOneDriveRestore(
          showMessage: _showMessage,
          openUsSheet: _openUsSheet,
          loadAppData: _loadAppData,
        ),
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
      isWriteLocked: _sync.isWriteLocked,
      topContentInset: _topStatusInset,
      onWriteBlocked: _sync.showWriteLockedMessage,
      onOpenSchedules: (date) => _openScheduleManager(initialDate: date),
      onOpenEntry: _openEntryDetail,
      onEditEntry: _editEntry,
      onDeleteEntry: _deleteEntry,
      syncStatusRevision: _sync.syncStatusRevision,
      isSyncingOneDrive: _sync.isSyncingOneDrive,
      isCancellingOneDriveSync: _sync.isCancellingOneDriveSync,
      oneDriveSyncProgress: _sync.oneDriveSyncProgress,
      oneDriveSyncLabel: _sync.oneDriveSyncLabel,
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
                  (!_sync.isSyncingOneDrive || _isTimelineBarVisible) &&
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
