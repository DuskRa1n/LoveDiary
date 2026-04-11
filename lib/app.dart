import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'data/diary_storage.dart';
import 'models/diary_models.dart';
import 'sync/diary_sync_executor.dart';
import 'sync/sync_models.dart';
import 'sync/webdav/jianguoyun_debug_bootstrap.dart';
import 'sync/webdav/webdav_models.dart';
import 'sync/webdav/webdav_remote_source.dart';
import 'ui/diary_design.dart';
import 'ui/real_today_tab.dart';
import 'ui/real_timeline_tab.dart';
import 'ui/real_us_tab.dart';
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
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: DiaryPalette.white.withValues(alpha: 0.92),
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
          backgroundColor: DiaryPalette.blush,
          foregroundColor: DiaryPalette.ink,
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: DiaryPalette.white.withValues(alpha: 0.9),
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

class _LoveDailyShellState extends State<LoveDailyShell> {
  List<DiaryEntry> _entries = const [];
  CoupleProfile _profile = DiaryStorage.seedProfile();
  bool _isLoaded = false;
  bool _isEditingJianguoyun = false;
  bool _isSyncingJianguoyun = false;
  bool _hasHandledStartupRecovery = false;
  int _currentIndex = 0;
  DateTime? _lastSyncedAt;
  WebDavSyncConfig? _jianguoyunConfig;
  String? _storageRootPath;
  String? _startupLoadError;

  @override
  void initState() {
    super.initState();
    _loadAppData();
  }

  Future<void> _loadAppData() async {
    var currentStep = 'bootstrapDebugJianguoyunConfig';
    String? resolvedRootPath;
    try {
      await _bootstrapDebugJianguoyunConfig();
      currentStep = 'loadEntries';
      final entries = await widget.storage.loadEntries();
      currentStep = 'loadProfile';
      final profile = await widget.storage.loadProfile();
      currentStep = 'resolveRootDirectory';
      final rootDirectory = await widget.storage.resolveRootDirectory();
      resolvedRootPath = rootDirectory.path;
      currentStep = 'loadSyncState';
      final syncState = await widget.storage.loadSyncState();
      currentStep = 'loadWebDavSyncConfig';
      final jianguoyunConfig = await widget.storage.loadWebDavSyncConfig();

      if (!mounted) {
        return;
      }

      setState(() {
        _entries = entries;
        _profile = profile;
        _lastSyncedAt = syncState.lastSyncedAt;
        _jianguoyunConfig = jianguoyunConfig;
        _storageRootPath = rootDirectory.path;
        _startupLoadError = null;
        _isLoaded = true;
      });

      if (!_hasHandledStartupRecovery &&
          _shouldOfferStartupRecovery(
            entries: entries,
            profile: profile,
            jianguoyunConfig: jianguoyunConfig,
          )) {
        _hasHandledStartupRecovery = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _offerStartupRecovery();
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
        _jianguoyunConfig = null;
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
                if (mounted) {
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

  Future<void> _bootstrapDebugJianguoyunConfig() async {
    if (!kDebugMode || !kDebugJianguoyunBootstrapEnabled) {
      return;
    }

    final existingConfig = await widget.storage.loadWebDavSyncConfig();
    if (existingConfig != null) {
      return;
    }

    await widget.storage.saveWebDavSyncConfig(kDebugJianguoyunBootstrapConfig);
    await widget.storage.saveSyncState(SyncState.initial());
    await widget.storage.saveTombstones(const []);
  }

  bool _shouldOfferStartupRecovery({
    required List<DiaryEntry> entries,
    required CoupleProfile profile,
    required WebDavSyncConfig? jianguoyunConfig,
  }) {
    final hasLocalData = entries.isNotEmpty || profile.isOnboarded;
    return !hasLocalData;
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
    final entry = await Navigator.of(context).push<DiaryEntry>(
      MaterialPageRoute(
        builder: (_) => CreateEntryPage(
          storage: widget.storage,
          initialEntry: initialEntry,
          rootDirectoryPath: _storageRootPath,
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

    setState(() {
      _currentIndex = 1;
    });

    if (!mounted) {
      return savedEntry;
    }

    final message = initialEntry == null ? '日记已保存到本地' : '日记已更新';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    return savedEntry;
  }

  Future<DiaryEntry> _addComment(String entryId, DiaryComment comment) async {
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
    return updatedEntry;
  }

  Future<DiaryEntry?> _editEntry(DiaryEntry entry) {
    return _openEditor(initialEntry: entry);
  }

  Future<void> _deleteEntry(DiaryEntry entry) async {
    await widget.storage.deleteEntry(entry);
    await _reloadEntries();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除《${entry.title}》')),
    );
  }

  Future<void> _openProfileEditor({required bool firstSetup}) async {
    final updatedProfile = await Navigator.of(context).push<CoupleProfile>(
      MaterialPageRoute(
        fullscreenDialog: !firstSetup,
        builder: (_) => ProfileSetupPage(
          initialProfile: _profile,
          isFirstSetup: firstSetup,
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
        builder: (_) => DustbinPage(storage: widget.storage),
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
          entry: entry,
          rootDirectoryPath: _storageRootPath,
          onAddComment: _addComment,
          onEditEntry: _editEntry,
          onDeleteEntry: _deleteEntry,
        ),
      ),
    );
  }

  Future<void> _openJianguoyunSettings() async {
    if (_isEditingJianguoyun || _isSyncingJianguoyun) {
      return;
    }

    final defaults = _JianguoyunConfigFormData(
      serverUrl: _jianguoyunConfig?.serverUrl ?? 'https://dav.jianguoyun.com/dav/',
      username: _jianguoyunConfig?.username ?? '',
      password: _jianguoyunConfig?.password ?? '',
      remoteFolder: _jianguoyunConfig?.remoteFolder ?? 'love_diary',
    );
    final formData = await _showJianguoyunConfigPage(defaults);
    if (formData == null) {
      return;
    }

    setState(() {
      _isEditingJianguoyun = true;
    });

    try {
      final config = WebDavSyncConfig(
        serverUrl: formData.serverUrl,
        username: formData.username,
        password: formData.password,
        remoteFolder: formData.remoteFolder,
      );
      final remoteSource = WebDavRemoteSource(storage: widget.storage);
      await remoteSource.validateConfig(config);
      await widget.storage.saveWebDavSyncConfig(config);
      if (!mounted) {
        return;
      }

      setState(() {
        _jianguoyunConfig = config;
      });
      _showMessage('坚果云已连接');
    } on WebDavSyncException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('连接坚果云失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEditingJianguoyun = false;
        });
      }
    }
  }

  Future<void> _syncWithJianguoyun() async {
    if (_jianguoyunConfig == null || _isSyncingJianguoyun || _isEditingJianguoyun) {
      return;
    }

    setState(() {
      _isSyncingJianguoyun = true;
    });

    try {
      final remoteSource = WebDavRemoteSource(storage: widget.storage);
      final executor = DiarySyncExecutor(
        storage: widget.storage,
        remoteSource: remoteSource,
      );
      final result = await executor.sync();
      await _loadAppData();

      if (!mounted) {
        return;
      }

      if (result.hasConflicts) {
        await _handleSyncConflicts(result.conflictPaths);
        return;
      }

      final summary =
          '同步完成：上传 ${result.uploadedPaths.length}，下载 ${result.downloadedPaths.length}，远端删除 ${result.deletedRemotePaths.length}，本地删除 ${result.deletedLocalPaths.length}';
      _showMessage(summary);
    } on WebDavSyncException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('同步失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingJianguoyun = false;
        });
      }
    }
  }

  Future<void> _handleSyncConflicts(List<String> conflictPaths) async {
    final result = await Navigator.of(context).push<SyncConflictResolutionResult>(
      MaterialPageRoute(
        builder: (_) => SyncConflictPage(conflictPaths: conflictPaths),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _isSyncingJianguoyun = true;
    });

    try {
      final executor = DiarySyncExecutor(
        storage: widget.storage,
        remoteSource: WebDavRemoteSource(storage: widget.storage),
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
    } on WebDavSyncException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('处理冲突失败：' + error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingJianguoyun = false;
        });
      }
    }
  }

  Future<void> _offerStartupRecovery() async {
    final shouldRestore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('要先从坚果云恢复吗？'),
          content: Text(
            _jianguoyunConfig == null
                ? '当前本地还是空的。你可以先连接坚果云并导入已有内容，也可以直接从本地开始。'
                : '当前本地还是空的。你可以先从坚果云拉取已有数据，也可以直接从本地开始。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('从本地开始'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_jianguoyunConfig == null ? '连接并恢复' : '从坚果云恢复'),
            ),
          ],
        );
      },
    );

    if (shouldRestore != true) {
      return;
    }

    if (_jianguoyunConfig == null) {
      await _openJianguoyunSettings();
      if (!mounted || _jianguoyunConfig == null) {
        _showMessage('还没有完成坚果云配置，先按本地开始。');
        return;
      }
    }

    await _restoreFromJianguoyunAtStartup();
  }


  Future<void> _restoreFromJianguoyunAtStartup() async {
    if (_jianguoyunConfig == null || _isSyncingJianguoyun) {
      return;
    }

    setState(() {
      _isSyncingJianguoyun = true;
    });

    try {
      final remoteSource = WebDavRemoteSource(storage: widget.storage);
      final snapshot = await remoteSource.fetchSnapshot();
      if (snapshot.files.isEmpty) {
        if (mounted) {
          _showMessage('坚果云里还没有可恢复的数据。');
        }
        return;
      }

      for (final file in snapshot.files) {
        final targetAbsolutePath = await widget.storage.resolveSyncFileAbsolutePath(
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

      final localFiles = await widget.storage.listSyncFiles();
      await widget.storage.saveSyncState(
        SyncState(
          lastSyncedAt: DateTime.now(),
          lastKnownRemoteCursor: snapshot.cursor,
          lastKnownLocalFingerprints: {
            for (final file in localFiles) file.relativePath: file.fingerprint,
          },
          lastKnownRemoteRevisions: {
            for (final file in snapshot.files) file.relativePath: file.revision,
          },
        ),
      );
      await _loadAppData();

      if (mounted) {
        _showMessage('已从坚果云恢复本地数据。');
      }
    } on WebDavSyncException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('恢复失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingJianguoyun = false;
        });
      }
    }
  }

  Future<void> _disconnectJianguoyun() async {
    if (_jianguoyunConfig == null || _isEditingJianguoyun || _isSyncingJianguoyun) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('断开坚果云'),
          content: const Text('这只会移除当前设备的坚果云配置，不会删除本地数据或云端文件。'),
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
      return;
    }

    await widget.storage.clearWebDavSyncConfig();
    if (!mounted) {
      return;
    }

    setState(() {
      _jianguoyunConfig = null;
    });
    _showMessage('已断开坚果云');
  }

  Future<_JianguoyunConfigFormData?> _showJianguoyunConfigPage(
    _JianguoyunConfigFormData defaults,
  ) async {
    return Navigator.of(context).push<_JianguoyunConfigFormData>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _JianguoyunConfigPage(defaults: defaults),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_profile.isOnboarded) {
      return ProfileSetupPage(
        initialProfile: _profile,
        isFirstSetup: true,
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
        rootDirectoryPath: _storageRootPath,
        onOpenEntry: _openEntryDetail,
      ),
      RealTimelineTab(
        entries: _entries,
        rootDirectoryPath: _storageRootPath,
        onOpenEntry: _openEntryDetail,
        onEditEntry: _editEntry,
        onDeleteEntry: _deleteEntry,
      ),
      RealUsTab(
        profile: _profile,
        entries: _entries,
        jianguoyunConfig: _jianguoyunConfig,
        lastSyncedAt: _lastSyncedAt,
        isEditingJianguoyun: _isEditingJianguoyun,
        isSyncingJianguoyun: _isSyncingJianguoyun,
        onEditProfile: () => _openProfileEditor(firstSetup: false),
        onOpenDustbin: _openDustbin,
        onOpenJianguoyunSettings: _openJianguoyunSettings,
        onSyncJianguoyun: _syncWithJianguoyun,
        onDisconnectJianguoyun: _disconnectJianguoyun,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildStartupErrorBanner(),
            Expanded(
              child: IndexedStack(index: _currentIndex, children: pages),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('写日记'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: '今天',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded),
            label: '回忆',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt_rounded),
            label: '我们',
          ),
        ],
      ),
    );
  }
}

class DustbinPage extends StatefulWidget {
  const DustbinPage({super.key, required this.storage});

  final DiaryStorage storage;

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
    _loadDeletedEntries();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已恢复 ${deletedEntry.entry.title}')),
    );
  }

  Future<void> _deleteForever(DeletedDiaryEntry deletedEntry) async {
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
                                    style: Theme.of(context).textTheme.bodyMedium
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
                                        label: '剩余 ${_remainingDays(deletedEntry)} 天',
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
                                            : () => _restoreEntry(deletedEntry),
                                        icon: const Icon(Icons.undo_rounded),
                                        label: const Text('恢复'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: isProcessing
                                            ? null
                                            : () => _deleteForever(deletedEntry),
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
    this.onComplete,
  });

  final CoupleProfile initialProfile;
  final bool isFirstSetup;
  final Future<void> Function(CoupleProfile profile)? onComplete;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _maleNameController;
  late final TextEditingController _femaleNameController;
  late DateTime _togetherSince;

  @override
  void initState() {
    super.initState();
    _maleNameController = TextEditingController(
      text: widget.initialProfile.maleName,
    );
    _femaleNameController = TextEditingController(
      text: widget.initialProfile.femaleName,
    );
    _togetherSince = widget.initialProfile.togetherSince;
  }

  @override
  void dispose() {
    _maleNameController.dispose();
    _femaleNameController.dispose();
    super.dispose();
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final profile = widget.initialProfile.copyWith(
      maleName: _maleNameController.text.trim(),
      femaleName: _femaleNameController.text.trim(),
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
                title: widget.isFirstSetup ? '先把故事起个头' : '更新你们的资料',
                subtitle: widget.isFirstSetup
                    ? '把名字和在一起的日期填好，首页和统计会自动带上这些信息。'
                    : '这些信息会同步影响首页展示、统计和纪念日标记。',
              ),
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
                    OutlinedButton.icon(
                      onPressed: _pickTogetherSince,
                      icon: const Icon(Icons.favorite_rounded),
                      label: Text('在一起的日期：${formatDiaryDate(_togetherSince)}'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submit,
                child: Text(widget.isFirstSetup ? '开始记录' : '保存资料'),
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
    required this.entry,
    required this.rootDirectoryPath,
    required this.onAddComment,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final DiaryEntry entry;
  final String? rootDirectoryPath;
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
  String _selectedAuthor = '你';

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
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
          author: _selectedAuthor,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评论保存失败，请稍后再试')),
      );
    }
  }

  Future<void> _editEntry() async {
    final updatedEntry = await widget.onEditEntry(_entry);
    if (updatedEntry == null || !mounted) {
      return;
    }

    setState(() {
      _entry = updatedEntry;
    });
  }

  Future<void> _deleteEntry() async {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('日记详情'),
        actions: [
          IconButton(
            onPressed: _editEntry,
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑日记',
          ),
          IconButton(
            onPressed: _deleteEntry,
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
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ['你', '她'].map((author) {
                      return ChoiceChip(
                        label: Text(author),
                        selected: _selectedAuthor == author,
                        onSelected: (_) {
                          setState(() {
                            _selectedAuthor = author;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _commentController,
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
                      onPressed: _isSavingComment ? null : _submitComment,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text(_isSavingComment ? '保存中...' : '发表评论'),
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
              ..._entry.comments.map((comment) => CommentCard(comment: comment)),
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
    this.initialEntry,
    this.rootDirectoryPath,
  });

  final DiaryStorage storage;
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

  bool get _isEditMode => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.initialEntry?.title ?? '',
    );
    _contentController = TextEditingController(
      text: widget.initialEntry?.content ?? '',
    );
    _selectedDate = widget.initialEntry?.createdAt ?? DateTime.now();
    _selectedMood = widget.initialEntry?.mood ?? kDiaryMoods.first;
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
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
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
        imageQuality:
            importMode == _AttachmentImportMode.compressed ? 85 : null,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片导入失败，请检查权限或稍后再试')),
      );
    }
  }

  Future<void> _removeAttachment(DiaryAttachment attachment) async {
    if (attachment.path.startsWith('drafts/')) {
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
          content: Text(
            _isEditMode
                ? '你刚刚修改的内容还没有保存。'
                : '这篇日记还没有保存，可以先存成草稿。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_EditorExitAction.cancel),
              child: const Text('继续编辑'),
            ),
            if (!_isEditMode)
              TextButton(
                onPressed: () => Navigator.of(context).pop(_EditorExitAction.saveDraft),
                child: const Text('存为草稿'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_EditorExitAction.discard),
              child: const Text('放弃'),
            ),
          ],
        );
      },
    );

    switch (action) {
      case _EditorExitAction.saveDraft:
        await _saveDraft();
        return true;
      case _EditorExitAction.discard:
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final originalCreatedAt = widget.initialEntry?.createdAt ?? now;

    final entry = DiaryEntry(
      id: widget.initialEntry?.id ?? 'entry_${now.microsecondsSinceEpoch}',
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
        .where((attachment) => attachment.path.startsWith('drafts/'))
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
      if (current.id != baseline.id || current.path != baseline.path) {
        return false;
      }
    }
    return true;
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

    return WillPopScope(
      onWillPop: _confirmExit,
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
              TextButton(onPressed: _saveDraft, child: const Text('存草稿')),
            TextButton(onPressed: _submit, child: const Text('保存')),
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
                  title: _isEditMode ? '把这篇日记调整完整' : '记录今天的小瞬间',
                  subtitle: _isEditMode
                      ? '支持修改标题、内容、心情、日期和附图，保存后会回到时间线。'
                      : '这条路径已经接通了草稿、本地保存、附图和评论，先把真实使用体验做顺。',
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
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _isPickingImages ? null : _pickImages,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _attachments.isEmpty
                              ? (_isPickingImages ? '处理中...' : '添加照片')
                              : '已添加 ${_attachments.length} 张照片',
                        ),
                      ),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        EditableAttachmentGrid(
                          attachments: _attachments,
                          rootDirectoryPath: widget.rootDirectoryPath,
                          onRemove: (attachment) {
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
                  onPressed: _submit,
                  icon: const Icon(Icons.favorite_rounded),
                  label: Text(_isEditMode ? '保存修改' : '保存这篇日记'),
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
            '把还来不及忘记的小瞬间，好好留下来。',
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
              '这一版先把真实使用路径跑顺：引导、写日记、附图、评论、本地保存都已经接起来了。',
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
  });

  final DiaryAttachment attachment;
  final String? rootDirectoryPath;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (attachment.path.isEmpty || kIsWeb) {
      return _AttachmentPlaceholder(width: width, height: height);
    }

    return Image.file(
      File(resolveStoredPath(rootDirectoryPath, attachment.path)),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) =>
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
      child: const Icon(
        Icons.image_outlined,
        color: Color(0xFFC85C8E),
      ),
    );
  }
}

enum _EditorExitAction { cancel, saveDraft, discard }

enum _AttachmentImportMode { compressed, original }

enum _EntryCardAction { edit, delete }

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
                  formatDiaryShortDate(comment.createdAt),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: DiaryPalette.wine,
                  ),
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

class _JianguoyunConfigFormData {
  const _JianguoyunConfigFormData({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remoteFolder,
  });

  final String serverUrl;
  final String username;
  final String password;
  final String remoteFolder;
}

class _JianguoyunConfigPage extends StatefulWidget {
  const _JianguoyunConfigPage({required this.defaults});

  final _JianguoyunConfigFormData defaults;

  @override
  State<_JianguoyunConfigPage> createState() => _JianguoyunConfigPageState();
}

class _JianguoyunConfigPageState extends State<_JianguoyunConfigPage> {
  late final TextEditingController _serverUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _remoteFolderController;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(text: widget.defaults.serverUrl);
    _usernameController = TextEditingController(text: widget.defaults.username);
    _passwordController = TextEditingController(text: widget.defaults.password);
    _remoteFolderController = TextEditingController(
      text: widget.defaults.remoteFolder,
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remoteFolderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('配置坚果云'),
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
              eyebrow: '同步配置',
              title: '连接坚果云',
              subtitle: '填写 WebDAV 地址、账号和应用密码。建议使用第三方应用密码，不要直接使用登录密码。',
            ),
            const SizedBox(height: 20),
            DiaryPanel(
              child: Column(
                children: [
                  TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      labelText: 'WebDAV 地址',
                      hintText: 'https://dav.jianguoyun.com/dav/',
                    ),
                  ),
            const SizedBox(height: 12),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: '坚果云账号',
                      hintText: '输入你的坚果云用户名',
                    ),
                  ),
            const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: '应用密码',
                      hintText: '输入坚果云第三方应用密码',
                    ),
                    obscureText: true,
                  ),
            const SizedBox(height: 12),
                  TextField(
                    controller: _remoteFolderController,
                    decoration: const InputDecoration(
                      labelText: '远端目录',
                      hintText: '默认是 love_diary',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                final serverUrl = _serverUrlController.text.trim();
                final username = _usernameController.text.trim();
                final password = _passwordController.text;
                final remoteFolder = _remoteFolderController.text.trim().isEmpty
                    ? 'love_diary'
                    : _remoteFolderController.text.trim();
                if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
                  return;
                }
                Navigator.of(context).pop(
                  _JianguoyunConfigFormData(
                    serverUrl: serverUrl,
                    username: username,
                    password: password,
                    remoteFolder: remoteFolder,
                  ),
                );
              },
              child: const Text('保存并测试'),
            ),
          ],
        ),
      ),
    );
  }
}




