import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'secret_store.dart';
import '../models/diary_models.dart';
import '../sync/onedrive/onedrive_models.dart';
import '../sync/sync_models.dart';
import '../utils/app_log.dart';
import '../utils/background_task.dart';

class StorageMaintenanceResult {
  const StorageMaintenanceResult({
    required this.repairedEntries,
    required this.migratedAttachments,
    required this.missingAttachments,
  });

  final int repairedEntries;
  final int migratedAttachments;
  final int missingAttachments;

  bool get changed => repairedEntries > 0 || migratedAttachments > 0;
}

class AppSelfMaintenanceResult {
  const AppSelfMaintenanceResult({
    required this.indexedEntries,
    required this.deletedTemporaryFiles,
    required this.purgedDustbinEntries,
    required this.repairedSyncStates,
  });

  final int indexedEntries;
  final int deletedTemporaryFiles;
  final int purgedDustbinEntries;
  final int repairedSyncStates;

  bool get changed =>
      deletedTemporaryFiles > 0 ||
      purgedDustbinEntries > 0 ||
      repairedSyncStates > 0;
}

class _AttachmentPreparationResult {
  const _AttachmentPreparationResult({
    required this.attachment,
    required this.changed,
    required this.missingSource,
    this.obsoletePaths = const [],
  });

  final DiaryAttachment attachment;
  final bool changed;
  final bool missingSource;
  final List<String> obsoletePaths;
}

class DiaryStorage {
  DiaryStorage({
    this.rootDirectoryPath,
    this.nowProvider = DateTime.now,
    SecretStore? secretStore,
  }) : _secretStoreOverride = secretStore;

  static const MethodChannel _platformPathsChannel = MethodChannel(
    'love_diary/platform_paths',
  );
  static const MethodChannel _imageCodecChannel = MethodChannel(
    'love_diary/image_codec',
  );
  static final SecretStore _defaultSecretStore = FlutterSecretStore();

  final String? rootDirectoryPath;
  final DateTime Function() nowProvider;
  final SecretStore? _secretStoreOverride;
  bool _hasPurgedDustbin = false;
  Directory? _cachedRootDirectory;

  static const _profileFileName = 'profile.json';
  static const _localSettingsFileName = 'local_settings.json';
  static const _schedulesFileName = 'schedules.json';
  static const _entriesDirectoryName = 'entries';
  static const _attachmentsDirectoryName = 'attachments';
  static const _dustbinDirectoryName = 'dustbin';
  static const _dustbinEntriesDirectoryName = 'entries';
  static const _dustbinAttachmentsDirectoryName = 'attachments';
  static const _cacheDirectoryName = 'cache';
  static const _manifestFileName = 'manifest.json';
  static const _draftsDirectoryName = 'drafts';
  static const _draftAttachmentsDirectoryName = 'attachments';
  static const _entryDraftFileName = 'entry_draft.json';
  static const _syncDirectoryName = 'sync';
  static const _syncStateFileName = 'state.json';
  static const _oneDriveSyncStateFileName = 'onedrive_state.json';
  static const _tombstonesFileName = 'tombstones.json';
  static const _oneDriveConfigFileName = 'onedrive_account.json';
  static const _backupFileSuffix = '.bak';
  static const _dustbinRetention = Duration(days: 7);
  static const _imageTransformTimeout = Duration(seconds: 20);
  static const _oneDriveAccessTokenKey = 'onedrive_access_token';
  static const _oneDriveRefreshTokenKey = 'onedrive_refresh_token';

  SecretStore get _secretStore => _secretStoreOverride ?? _defaultSecretStore;

  Future<List<DiaryEntry>> loadEntries() async {
    // 回收站清理放到后台，不阻塞主加载
    unawaitedLogged(
      'Purge expired dustbin entries failed',
      _purgeDustbinIfNeeded,
    );
    final rootDirectory = await _ensureRootDirectory();
    final entriesDirectory = Directory(
      _join(rootDirectory.path, _entriesDirectoryName),
    );

    if (!await entriesDirectory.exists()) {
      return const [];
    }

    final files = await entriesDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    if (files.isEmpty) {
      return const [];
    }

    final entries = (await Future.wait(
      files.map((file) => _readEntryFile(rootDirectory.path, file)),
    )).whereType<DiaryEntry>().toList();
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<DiaryEntry?> _readEntryFile(String rootPath, File file) async {
    try {
      final fileName = file.uri.pathSegments.last;
      if (!fileName.endsWith('.json')) {
        return null;
      }
      final trustedEntryId = fileName.substring(0, fileName.length - 5);
      if (!SyncFilePolicy.isSafeId(trustedEntryId)) {
        return null;
      }
      final jsonMap = await _readJsonMapWithBackup(file, '读取日记文件');
      if (jsonMap == null) {
        return null;
      }
      final entry = DiaryEntry.fromJson(jsonMap);
      final sanitizedEntry = await _sanitizeLoadedEntry(
        rootPath: rootPath,
        trustedEntryId: trustedEntryId,
        entry: entry,
      );
      if (sanitizedEntry.id != entry.id ||
          !_attachmentsEqual(sanitizedEntry.attachments, entry.attachments)) {
        await _writeJsonAtomically(file, sanitizedEntry.toJson());
      }
      return sanitizedEntry;
    } catch (error, stackTrace) {
      AppLog.error('读取条目文件失败', error, stackTrace);
      return null;
    }
  }

  bool _attachmentsEqual(List<DiaryAttachment> a, List<DiaryAttachment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].path != b[i].path ||
          a[i].originalName != b[i].originalName) {
        return false;
      }
    }
    return true;
  }

  Future<void> saveEntries(List<DiaryEntry> entries) async {
    final rootDirectory = await _ensureRootDirectory();
    final entriesDirectory = Directory(
      _join(rootDirectory.path, _entriesDirectoryName),
    );
    if (!await entriesDirectory.exists()) {
      await entriesDirectory.create(recursive: true);
    }

    final normalizedEntries = <DiaryEntry>[];
    for (final entry in entries) {
      normalizedEntries.add(await _normalizeEntryForSave(entry));
    }

    final entryIds = normalizedEntries.map((entry) => entry.id).toSet();
    for (final entry in normalizedEntries) {
      final entryFile = _entryFileAt(rootDirectory.path, entry.id);
      await _writeJsonAtomically(entryFile, entry.toJson());
    }

    final existingFiles = await entriesDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    for (final file in existingFiles) {
      final fileName = file.uri.pathSegments.last;
      final id = fileName.replaceAll('.json', '');
      if (!entryIds.contains(id)) {
        await file.delete();
      }
    }

    await _writeManifestCache(normalizedEntries);
  }

  Future<DiaryEntry> saveEntry(DiaryEntry entry) async {
    final safeEntry = entry.copyWith(
      id: _normalizeSafeStorageId(entry.id, fallbackPrefix: 'entry'),
    );
    final normalizedEntry = await _normalizeEntryForSave(safeEntry);
    final rootDirectory = await _ensureRootDirectory();

    // 读取单个条目而非全部条目
    final previousEntry = await _readSingleEntry(
      rootDirectory.path,
      normalizedEntry.id,
    );

    // 写入当前条目文件
    await _writeJsonAtomically(
      _entryFileAt(rootDirectory.path, normalizedEntry.id),
      normalizedEntry.toJson(),
    );

    // 更新manifest缓存（增量方式）
    await _updateManifestCacheEntry(rootDirectory.path, normalizedEntry);

    // 清理附件
    final removedAttachments = _collectRemovedAttachments(
      previousEntry: previousEntry,
      nextEntry: normalizedEntry,
    );
    await deleteAttachments(removedAttachments);
    await _removeTombstones([
      _entryRelativePath(normalizedEntry.id),
      ...normalizedEntry.attachments.expand(
        (attachment) => attachment.storedPaths,
      ),
    ]);
    if (removedAttachments.isNotEmpty) {
      await _appendTombstones(
        removedAttachments
            .expand((attachment) => attachment.storedPaths)
            .toList(),
      );
    }

    return normalizedEntry;
  }

  Future<void> deleteEntry(DiaryEntry entry) async {
    await _moveEntryToDustbin(entry);
    final rootDirectory = await _ensureRootDirectory();
    final entryFile = _entryFileAt(rootDirectory.path, entry.id);
    if (await entryFile.exists()) {
      await entryFile.delete();
    }
    await _removeManifestCacheEntry(rootDirectory.path, entry.id);
    await _appendTombstones([
      _entryRelativePath(entry.id),
      ...entry.attachments.expand((attachment) => attachment.storedPaths),
    ]);
  }

  Future<List<DeletedDiaryEntry>> loadDustbinEntries() async {
    await _purgeDustbinIfNeeded();
    final rootDirectory = await _ensureRootDirectory();
    final dustbinEntriesDirectory = Directory(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
      ),
    );
    if (!await dustbinEntriesDirectory.exists()) {
      return const [];
    }

    final files = await dustbinEntriesDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (files.isEmpty) {
      return const [];
    }

    final deletedEntries = <DeletedDiaryEntry>[];
    for (final file in files) {
      try {
        final fileName = file.uri.pathSegments.last;
        final trustedEntryId = fileName.endsWith('.json')
            ? fileName.substring(0, fileName.length - 5)
            : '';
        if (!SyncFilePolicy.isSafeId(trustedEntryId)) {
          continue;
        }
        final jsonMap =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final deletedEntry = DeletedDiaryEntry.fromJson(jsonMap);
        final sanitizedEntry = await _sanitizeLoadedEntry(
          rootPath: rootDirectory.path,
          trustedEntryId: trustedEntryId,
          entry: deletedEntry.entry,
        );
        deletedEntries.add(
          DeletedDiaryEntry(
            entry: sanitizedEntry,
            deletedAt: deletedEntry.deletedAt,
          ),
        );
      } catch (error) {
        AppLog.error('读取回收站条目失败', error);
        continue;
      }
    }
    deletedEntries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return deletedEntries;
  }

  Future<void> restoreDeletedEntry(DeletedDiaryEntry deletedEntry) async {
    final rootDirectory = await _ensureRootDirectory();
    final safeEntryId = _normalizeSafeStorageId(
      deletedEntry.entry.id,
      fallbackPrefix: 'entry',
    );
    final restoredEntry = deletedEntry.entry.id == safeEntryId
        ? deletedEntry.entry
        : deletedEntry.entry.copyWith(id: safeEntryId);
    final dustbinEntryFile = File(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
        '$safeEntryId.json',
      ),
    );
    if (await dustbinEntryFile.exists()) {
      await dustbinEntryFile.delete();
    }

    final dustbinAttachmentsDirectory = _dustbinAttachmentsDirectoryAt(
      rootDirectory.path,
      safeEntryId,
    );
    final entryAttachmentsDirectory = _entryAttachmentsDirectoryAt(
      rootDirectory.path,
      safeEntryId,
    );
    if (await dustbinAttachmentsDirectory.exists()) {
      await _deleteDirectoryIfExists(entryAttachmentsDirectory);
      await dustbinAttachmentsDirectory.rename(entryAttachmentsDirectory.path);
    }

    // 增量写入，不需要加载全部条目
    await _writeJsonAtomically(
      _entryFileAt(rootDirectory.path, restoredEntry.id),
      restoredEntry.toJson(),
    );
    await _updateManifestCacheEntry(rootDirectory.path, restoredEntry);
    await _removeTombstones([
      _entryRelativePath(restoredEntry.id),
      ...restoredEntry.attachments.expand(
        (attachment) => attachment.storedPaths,
      ),
    ]);
  }

  Future<void> permanentlyDeleteDeletedEntry(
    DeletedDiaryEntry deletedEntry,
  ) async {
    final rootDirectory = await _ensureRootDirectory();
    final safeEntryId = _normalizeSafeStorageId(
      deletedEntry.entry.id,
      fallbackPrefix: 'entry',
    );
    final dustbinEntryFile = File(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
        '$safeEntryId.json',
      ),
    );
    if (await dustbinEntryFile.exists()) {
      await dustbinEntryFile.delete();
    }

    await _deleteDirectoryIfExists(
      _dustbinAttachmentsDirectoryAt(rootDirectory.path, safeEntryId),
    );
    await _appendTombstones([
      _entryRelativePath(deletedEntry.entry.id),
      ...deletedEntry.entry.attachments.expand(
        (attachment) => attachment.storedPaths,
      ),
    ]);
  }

  Future<CoupleProfile> loadProfile() async {
    final rootDirectory = await _ensureRootDirectory();
    final profileFile = File(_join(rootDirectory.path, _profileFileName));
    final localRole = await _loadLocalCurrentUserRole(rootDirectory);
    if (!await profileFile.exists()) {
      return seedProfile().copyWith(currentUserRole: localRole);
    }

    try {
      final jsonMap = await _readJsonMapWithBackup(profileFile, '加载个人资料');
      if (jsonMap == null) {
        return seedProfile().copyWith(currentUserRole: localRole);
      }
      final legacyRole = CoupleProfile.currentUserRoleFromJson(jsonMap);
      final currentUserRole = localRole ?? legacyRole;
      final profile = CoupleProfile.fromJson(
        jsonMap,
        currentUserRole: currentUserRole,
      );
      if (localRole == null && legacyRole != null) {
        await _saveLocalCurrentUserRole(rootDirectory, legacyRole);
      }
      if (jsonMap.containsKey('current_user_role')) {
        await _writeJsonAtomically(profileFile, profile.toJson());
      }
      return profile;
    } catch (error) {
      AppLog.error('加载个人资料失败', error);
      return seedProfile().copyWith(currentUserRole: localRole);
    }
  }

  Future<void> saveProfile(CoupleProfile profile) async {
    final rootDirectory = await _ensureRootDirectory();
    final profileFile = File(_join(rootDirectory.path, _profileFileName));
    await _writeJsonAtomically(profileFile, profile.toJson());
    await _saveLocalCurrentUserRole(rootDirectory, profile.currentUserRole);
  }

  Future<List<ScheduleItem>> loadSchedules() async {
    final rootDirectory = await _ensureRootDirectory();
    final schedulesFile = File(_join(rootDirectory.path, _schedulesFileName));
    if (!await schedulesFile.exists()) {
      return const [];
    }

    try {
      final raw = await _readJsonWithBackup(schedulesFile, '加载日程');
      if (raw == null) {
        return const [];
      }
      final rawItems = raw is Map<String, dynamic>
          ? raw['items'] as List<dynamic>? ?? <dynamic>[]
          : raw as List<dynamic>? ?? <dynamic>[];
      final schedules = rawItems
          .map((item) => ScheduleItem.fromJson(item as Map<String, dynamic>))
          .where((item) => item.title.trim().isNotEmpty)
          .toList();
      schedules.sort(ScheduleItem.compareByDate);
      return schedules;
    } catch (error) {
      AppLog.error('加载日程失败', error);
      return const [];
    }
  }

  Future<void> saveSchedules(List<ScheduleItem> schedules) async {
    final rootDirectory = await _ensureRootDirectory();
    final schedulesFile = File(_join(rootDirectory.path, _schedulesFileName));
    final normalizedSchedules = schedules.map(_normalizeSchedule).toList()
      ..sort(ScheduleItem.compareByDate);
    await _writeJsonAtomically(schedulesFile, {
      'version': 1,
      'items': normalizedSchedules.map((item) => item.toJson()).toList(),
    });
  }

  Future<ScheduleItem> saveSchedule(ScheduleItem schedule) async {
    final schedules = await loadSchedules();
    final normalizedSchedule = _normalizeSchedule(schedule);
    final index = schedules.indexWhere((item) => item.id == schedule.id);
    final nextSchedules = index == -1
        ? [normalizedSchedule, ...schedules]
        : [
            for (var itemIndex = 0; itemIndex < schedules.length; itemIndex++)
              if (itemIndex == index)
                normalizedSchedule
              else
                schedules[itemIndex],
          ];
    await saveSchedules(nextSchedules);
    return normalizedSchedule;
  }

  Future<void> deleteSchedule(ScheduleItem schedule) async {
    final schedules = [
      for (final item in await loadSchedules())
        if (item.id != schedule.id) item,
    ];
    await saveSchedules(schedules);
  }

  Future<Directory> ensureAttachmentsDirectory() async {
    final rootDirectory = await _ensureRootDirectory();
    final directory = Directory(
      _join(rootDirectory.path, _attachmentsDirectoryName),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<DiaryAttachment> importAttachment({
    required String sourcePath,
    required String fileName,
    bool keepOriginal = false,
  }) async {
    final rootDirectory = await _ensureRootDirectory();
    final now = DateTime.now();
    final attachmentId = 'att_${now.microsecondsSinceEpoch}';
    final attachmentDraftDirectory = Directory(
      _join(
        rootDirectory.path,
        _draftsDirectoryName,
        _draftAttachmentsDirectoryName,
        attachmentId,
      ),
    );
    if (!await attachmentDraftDirectory.exists()) {
      await attachmentDraftDirectory.create(recursive: true);
    }

    final extension = _extensionFromFileName(fileName);
    final sanitizedStem = _sanitizeFileName(_stemFromFileName(fileName));
    final fileStem = sanitizedStem.isEmpty
        ? attachmentId
        : '${attachmentId}_$sanitizedStem';
    final sourceFile = File(sourcePath);

    late final String storedFileName;
    if (keepOriginal) {
      storedFileName = '$fileStem$extension';
      final attachmentFile = File(
        _join(attachmentDraftDirectory.path, storedFileName),
      );
      await sourceFile.copy(attachmentFile.path);
    } else {
      storedFileName = await _writeCompressedAttachment(
        sourceFile: sourceFile,
        targetDirectory: attachmentDraftDirectory,
        fileStem: fileStem,
        sourceExtension: extension,
        maxDimension: 1600,
        jpegQuality: 86,
      );
    }

    final storedPath =
        '$_draftsDirectoryName/$_draftAttachmentsDirectoryName/$attachmentId/$storedFileName';

    return DiaryAttachment(
      id: attachmentId,
      path: storedPath,
      originalName: fileName,
      createdAt: now,
    );
  }

  Future<void> deleteAttachments(List<DiaryAttachment> attachments) async {
    if (attachments.isEmpty) {
      return;
    }

    final rootDirectory = await _ensureRootDirectory();
    for (final attachment in attachments) {
      for (final storedPath in attachment.storedPaths) {
        final relativePath = _safeStoredAttachmentPath(
          storedPath,
          allowDrafts: true,
        );
        if (relativePath == null) {
          continue;
        }

        final file = File(_resolveStoredPath(rootDirectory.path, relativePath));
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  Future<Directory> resolveRootDirectory() async {
    return _ensureRootDirectory();
  }

  Future<String> resolveSyncFileAbsolutePath(String relativePath) async {
    final rootDirectory = await _ensureRootDirectory();
    final safePath = _normalizeSyncBusinessPath(relativePath);
    return _resolveProtectedSyncPath(rootDirectory.path, safePath);
  }

  Future<void> deleteSyncFile(String relativePath) async {
    final rootDirectory = await _ensureRootDirectory();
    final protectedPath = _normalizeSyncBusinessPath(relativePath);

    final file = File(
      _resolveProtectedSyncPath(rootDirectory.path, protectedPath),
    );
    if (await file.exists()) {
      await file.delete();
    }

    final lastSeparatorIndex = protectedPath.lastIndexOf('/');
    if (lastSeparatorIndex != -1) {
      final directoryPath = protectedPath.substring(0, lastSeparatorIndex);
      final directory = Directory(
        _resolveProtectedSyncPath(rootDirectory.path, directoryPath),
      );
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
    }

    await _removeTombstones([protectedPath]);
  }

  Future<DiaryDraft?> loadEntryDraft() async {
    final rootDirectory = await _ensureRootDirectory();
    final draftFile = File(
      _join(rootDirectory.path, _draftsDirectoryName, _entryDraftFileName),
    );
    if (!await draftFile.exists()) {
      return null;
    }

    try {
      final jsonMap = await _readJsonMapWithBackup(draftFile, '加载草稿');
      if (jsonMap == null) {
        return null;
      }
      return DiaryDraft.fromJson(jsonMap);
    } catch (error) {
      AppLog.error('加载草稿失败', error);
      return null;
    }
  }

  Future<void> saveEntryDraft(DiaryDraft draft) async {
    final rootDirectory = await _ensureRootDirectory();
    final draftsDirectory = Directory(
      _join(rootDirectory.path, _draftsDirectoryName),
    );
    if (!await draftsDirectory.exists()) {
      await draftsDirectory.create(recursive: true);
    }

    final previousDraft = await loadEntryDraft();
    if (previousDraft != null) {
      final removedAttachments = _collectRemovedDraftAttachments(
        previousDraft.attachments,
        draft.attachments,
      );
      await deleteAttachments(removedAttachments);
    }

    final draftFile = File(
      _join(rootDirectory.path, _draftsDirectoryName, _entryDraftFileName),
    );
    await _writeJsonAtomically(draftFile, draft.toJson());
  }

  Future<void> clearEntryDraft() async {
    final rootDirectory = await _ensureRootDirectory();
    final previousDraft = await loadEntryDraft();
    if (previousDraft != null) {
      await deleteAttachments(previousDraft.attachments);
    }

    final draftFile = File(
      _join(rootDirectory.path, _draftsDirectoryName, _entryDraftFileName),
    );
    if (await draftFile.exists()) {
      await draftFile.delete();
    }

    await _deleteDirectoryIfExists(
      Directory(
        _join(
          rootDirectory.path,
          _draftsDirectoryName,
          _draftAttachmentsDirectoryName,
        ),
      ),
    );
  }

  Future<Directory> ensureSyncDirectory() async {
    final rootDirectory = await _ensureRootDirectory();
    final directory = Directory(_join(rootDirectory.path, _syncDirectoryName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<SyncState> loadSyncState([
    SyncProvider provider = SyncProvider.oneDrive,
  ]) async {
    final syncDirectory = await ensureSyncDirectory();
    final stateFile = File(
      _join(syncDirectory.path, _syncStateFileNameFor(provider)),
    );
    if (!await stateFile.exists() && provider == SyncProvider.oneDrive) {
      final legacyFile = File(_join(syncDirectory.path, _syncStateFileName));
      if (await legacyFile.exists()) {
        try {
          final jsonMap = await _readJsonMapWithBackup(legacyFile, '加载旧版同步状态');
          if (jsonMap == null) {
            return SyncState.initial();
          }
          return SyncState.fromJson(jsonMap);
        } catch (error) {
          AppLog.error('加载旧版同步状态失败', error);
          return SyncState.initial();
        }
      }
    }
    if (!await stateFile.exists()) {
      return SyncState.initial();
    }

    try {
      final jsonMap = await _readJsonMapWithBackup(stateFile, '加载同步状态');
      if (jsonMap == null) {
        return SyncState.initial();
      }
      return SyncState.fromJson(jsonMap);
    } catch (error) {
      AppLog.error('加载同步状态失败', error);
      return SyncState.initial();
    }
  }

  Future<void> saveSyncState(
    SyncState state, [
    SyncProvider provider = SyncProvider.oneDrive,
  ]) async {
    final syncDirectory = await ensureSyncDirectory();
    final stateFile = File(
      _join(syncDirectory.path, _syncStateFileNameFor(provider)),
    );
    await _writeJsonCompactAtomically(stateFile, state.toJson());
  }

  Future<void> resetSyncState([
    SyncProvider provider = SyncProvider.oneDrive,
  ]) async {
    final syncDirectory = await ensureSyncDirectory();
    final stateFile = File(
      _join(syncDirectory.path, _syncStateFileNameFor(provider)),
    );
    if (await stateFile.exists()) {
      await stateFile.delete();
    }
    if (provider == SyncProvider.oneDrive) {
      final legacyFile = File(_join(syncDirectory.path, _syncStateFileName));
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    }
  }

  Future<List<SyncTombstone>> loadTombstones() async {
    final syncDirectory = await ensureSyncDirectory();
    final tombstonesFile = File(_join(syncDirectory.path, _tombstonesFileName));
    if (!await tombstonesFile.exists()) {
      return const [];
    }

    try {
      final rawList = jsonDecode(await tombstonesFile.readAsString()) as List;
      return rawList
          .whereType<Map>()
          .map(
            (item) => SyncTombstone.fromJson(Map<String, dynamic>.from(item)),
          )
          .where(
            (item) => SyncFilePolicy.isSyncableBusinessPath(item.relativePath),
          )
          .toList();
    } catch (error) {
      AppLog.error('加载tombstones失败', error);
      return const [];
    }
  }

  Future<void> saveTombstones(List<SyncTombstone> tombstones) async {
    final syncDirectory = await ensureSyncDirectory();
    final tombstonesFile = File(_join(syncDirectory.path, _tombstonesFileName));
    await _writeJsonCompactAtomically(
      tombstonesFile,
      tombstones.map((item) => item.toJson()).toList(),
    );
  }

  Future<void> acknowledgeTombstones(List<String> rawPaths) async {
    final relativePaths = rawPaths
        .map(_safeSyncBusinessPathOrNull)
        .whereType<String>()
        .toSet();
    if (relativePaths.isEmpty) {
      return;
    }

    final tombstones = await loadTombstones();
    final filtered = tombstones
        .where((item) => !relativePaths.contains(item.relativePath))
        .toList();
    if (filtered.length != tombstones.length) {
      await saveTombstones(filtered);
    }
  }

  Future<OneDriveSyncConfig?> loadOneDriveSyncConfig() async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _oneDriveConfigFileName));
    if (!await configFile.exists()) {
      return null;
    }

    try {
      final jsonMap = await _readJsonMapWithBackup(
        configFile,
        '加载 OneDrive 配置',
      );
      if (jsonMap == null) {
        return null;
      }
      final config = OneDriveSyncConfig.fromJson(jsonMap);
      final accessToken =
          await _readOneDriveSecret(_oneDriveAccessTokenKey) ??
          jsonMap['access_token'] as String?;
      final refreshToken =
          await _readOneDriveSecret(_oneDriveRefreshTokenKey) ??
          jsonMap['refresh_token'] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        return null;
      }

      if ((jsonMap['access_token'] as String?)?.isNotEmpty ?? false) {
        await _saveOneDriveSecrets(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
        await _writeJsonCompactAtomically(configFile, config.toStorageJson());
      }

      return config.copyWith(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } catch (error) {
      AppLog.error('加载OneDrive配置失败', error);
      return null;
    }
  }

  Future<void> saveOneDriveSyncConfig(OneDriveSyncConfig config) async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _oneDriveConfigFileName));
    await _saveOneDriveSecrets(
      accessToken: config.accessToken,
      refreshToken: config.refreshToken,
    );
    await _writeJsonCompactAtomically(configFile, config.toStorageJson());
  }

  Future<void> clearOneDriveSyncConfig() async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _oneDriveConfigFileName));
    if (await configFile.exists()) {
      await configFile.delete();
    }
    await _clearOneDriveSecrets();
  }

  Future<List<LocalSyncFile>> listSyncFiles() async {
    await _purgeDustbinIfNeeded();
    final rootDirectory = await _ensureRootDirectory();
    final files = <LocalSyncFile>[];

    await for (final entity in rootDirectory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }

      final relativePath = _toRelativePath(rootDirectory.path, entity.path);
      if (!SyncFilePolicy.isSyncableBusinessPath(relativePath)) {
        continue;
      }

      final stat = await entity.stat();
      files.add(
        LocalSyncFile(
          relativePath: relativePath,
          absolutePath: entity.path,
          fingerprint: '${stat.size}:${stat.modified.millisecondsSinceEpoch}',
          modifiedAt: stat.modified,
          size: stat.size,
          isBinary: !_isJsonFile(relativePath),
        ),
      );
    }

    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return files;
  }

  Future<StorageMaintenanceResult> prepareFilesForSync() async {
    final rootDirectory = await _ensureRootDirectory();
    final entries = await loadEntries();
    if (entries.isEmpty) {
      return const StorageMaintenanceResult(
        repairedEntries: 0,
        migratedAttachments: 0,
        missingAttachments: 0,
      );
    }

    var repairedEntries = 0;
    var migratedAttachments = 0;
    var missingAttachments = 0;
    final obsoletePaths = <String>[];

    for (final entry in entries) {
      var entryChanged = false;
      final attachments = <DiaryAttachment>[];
      for (final attachment in entry.attachments) {
        final result = await _prepareAttachmentForSync(
          rootPath: rootDirectory.path,
          entryId: entry.id,
          attachment: attachment,
        );
        attachments.add(result.attachment);
        if (result.changed) {
          entryChanged = true;
          migratedAttachments += 1;
        }
        if (result.missingSource) {
          missingAttachments += 1;
        }
        obsoletePaths.addAll(result.obsoletePaths);
      }

      if (entryChanged) {
        repairedEntries += 1;
        final repairedEntry = entry.copyWith(attachments: attachments);
        await _writeJsonAtomically(
          _entryFileAt(rootDirectory.path, repairedEntry.id),
          repairedEntry.toJson(),
        );
        await _updateManifestCacheEntry(rootDirectory.path, repairedEntry);
      }
    }

    if (obsoletePaths.isNotEmpty) {
      await _appendTombstones(obsoletePaths);
      await _deleteObsoleteSyncFiles(rootDirectory.path, obsoletePaths);
    }

    return StorageMaintenanceResult(
      repairedEntries: repairedEntries,
      migratedAttachments: migratedAttachments,
      missingAttachments: missingAttachments,
    );
  }

  Future<AppSelfMaintenanceResult> runSelfMaintenance({
    Duration staleTemporaryFileAge = const Duration(hours: 6),
    Duration staleIncompleteSyncAge = const Duration(hours: 12),
  }) async {
    final rootDirectory = await _ensureRootDirectory();
    final deletedTemporaryFiles = await _deleteStaleTemporaryFiles(
      rootDirectory,
      staleTemporaryFileAge,
    );
    final purgedDustbinEntries = await purgeExpiredDustbinEntries();
    final entries = await loadEntries();
    await _writeManifestCache(entries);
    final repairedSyncStates = await _repairStaleIncompleteSyncStates(
      staleIncompleteSyncAge,
    );

    return AppSelfMaintenanceResult(
      indexedEntries: entries.length,
      deletedTemporaryFiles: deletedTemporaryFiles,
      purgedDustbinEntries: purgedDustbinEntries,
      repairedSyncStates: repairedSyncStates,
    );
  }

  Future<Directory> _ensureRootDirectory() async {
    final cached = _cachedRootDirectory;
    if (cached != null && await cached.exists()) {
      return cached;
    }

    final directory = rootDirectoryPath == null
        ? Directory(
            _join((await _resolveApplicationDocumentsPath()), 'love_diary'),
          )
        : Directory(rootDirectoryPath!);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final subdirectories = [
      _entriesDirectoryName,
      _attachmentsDirectoryName,
      _cacheDirectoryName,
      _draftsDirectoryName,
      _dustbinDirectoryName,
      _join(_dustbinDirectoryName, _dustbinEntriesDirectoryName),
      _join(_dustbinDirectoryName, _dustbinAttachmentsDirectoryName),
      _syncDirectoryName,
    ];

    await Future.wait(
      subdirectories.map((sub) async {
        final subDir = Directory(_join(directory.path, sub));
        if (!await subDir.exists()) {
          await subDir.create(recursive: true);
        }
      }),
    );

    _cachedRootDirectory = directory;
    return directory;
  }

  Future<String> _resolveApplicationDocumentsPath() async {
    if (Platform.isAndroid) {
      try {
        final path = await _platformPathsChannel.invokeMethod<String>(
          'getAppDocumentsDir',
        );
        if (path != null && path.isNotEmpty) {
          return path;
        }
      } catch (error) {
        AppLog.warn('获取Android文档路径失败: $error');
        // Fall back to path_provider below.
      }
    }

    return (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> _writeManifestCache(List<DiaryEntry> entries) async {
    final rootDirectory = await _ensureRootDirectory();
    final manifestFile = File(
      _join(rootDirectory.path, _cacheDirectoryName, _manifestFileName),
    );
    final manifest = {
      'version': 2,
      'generated_at': DateTime.now().toIso8601String(),
      'entries': entries
          .map(
            (entry) => {
              'id': entry.id,
              'created_at': entry.createdAt.toIso8601String(),
              'updated_at': entry.updatedAt?.toIso8601String(),
            },
          )
          .toList(),
    };
    await _writeJsonCompactAtomically(manifestFile, manifest);
  }

  Future<DiaryEntry?> _readSingleEntry(String rootPath, String entryId) async {
    final file = _entryFileAt(rootPath, entryId);
    if (!await file.exists()) {
      return null;
    }
    return _readEntryFile(rootPath, file);
  }

  Future<void> _updateManifestCacheEntry(
    String rootPath,
    DiaryEntry entry,
  ) async {
    final manifestFile = File(
      _join(rootPath, _cacheDirectoryName, _manifestFileName),
    );

    Map<String, dynamic> manifest;
    if (await manifestFile.exists()) {
      try {
        manifest =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
      } catch (error) {
        AppLog.error('读取manifest缓存失败', error);
        manifest = {'version': 2, 'entries': []};
      }
    } else {
      manifest = {'version': 2, 'entries': []};
    }

    final entries = (manifest['entries'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final index = entries.indexWhere((item) => item['id'] == entry.id);
    final entryData = {
      'id': entry.id,
      'created_at': entry.createdAt.toIso8601String(),
      'updated_at': entry.updatedAt?.toIso8601String(),
    };

    if (index == -1) {
      entries.insert(0, entryData);
    } else {
      entries[index] = entryData;
    }

    // 按创建时间排序
    entries.sort((a, b) {
      final aTime = DateTime.parse(a['created_at'] as String);
      final bTime = DateTime.parse(b['created_at'] as String);
      return bTime.compareTo(aTime);
    });

    manifest['entries'] = entries;
    manifest['generated_at'] = DateTime.now().toIso8601String();
    await _writeJsonCompactAtomically(manifestFile, manifest);
  }

  Future<void> _removeManifestCacheEntry(
    String rootPath,
    String entryId,
  ) async {
    final manifestFile = File(
      _join(rootPath, _cacheDirectoryName, _manifestFileName),
    );

    if (!await manifestFile.exists()) {
      return;
    }

    try {
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final entries = (manifest['entries'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((item) => item['id'] != entryId)
          .toList();
      manifest['entries'] = entries;
      manifest['generated_at'] = DateTime.now().toIso8601String();
      await _writeJsonCompactAtomically(manifestFile, manifest);
    } catch (error) {
      AppLog.error('移除manifest缓存条目失败', error);
    }
  }

  Future<DiaryEntry> _sanitizeLoadedEntry({
    required String rootPath,
    required String trustedEntryId,
    required DiaryEntry entry,
  }) async {
    final attachments = <DiaryAttachment>[];
    for (var index = 0; index < entry.attachments.length; index++) {
      final attachment = await _sanitizeAttachmentForStorage(
        rootPath: rootPath,
        attachment: entry.attachments[index],
        index: index,
        allowDrafts: false,
      );
      if (attachment != null) {
        // 如果有原图但缺少缩略图/预览图，本地按需生成
        attachments.add(attachment);
      }
    }
    return entry.copyWith(id: trustedEntryId, attachments: attachments);
  }

  Future<DiaryAttachment?> _sanitizeAttachmentForStorage({
    required String rootPath,
    required DiaryAttachment attachment,
    required int index,
    required bool allowDrafts,
  }) async {
    final attachmentId = _normalizeSafeStorageId(
      attachment.id,
      fallbackPrefix: 'att_$index',
    );
    final path = _safeStoredAttachmentPath(
      attachment.path,
      allowDrafts: allowDrafts,
    );

    if (path == null || path.isEmpty) {
      return null;
    }

    return attachment.copyWith(id: attachmentId, path: path);
  }

  Future<DiaryEntry> _normalizeEntryForSave(DiaryEntry entry) async {
    final rootDirectory = await _ensureRootDirectory();
    final entryId = _normalizeSafeStorageId(entry.id, fallbackPrefix: 'entry');
    final normalizedAttachments = <DiaryAttachment>[];
    for (var index = 0; index < entry.attachments.length; index++) {
      final attachment = await _sanitizeAttachmentForStorage(
        rootPath: rootDirectory.path,
        attachment: entry.attachments[index],
        index: index,
        allowDrafts: true,
      );
      if (attachment == null) {
        continue;
      }
      normalizedAttachments.add(
        await _normalizeAttachmentForEntry(
          entryId: entryId,
          attachment: attachment,
        ),
      );
    }

    return entry.copyWith(id: entryId, attachments: normalizedAttachments);
  }

  Future<_AttachmentPreparationResult> _prepareAttachmentForSync({
    required String rootPath,
    required String entryId,
    required DiaryAttachment attachment,
  }) async {
    final source = await _findExistingAttachmentFile(
      rootPath: rootPath,
      attachment: attachment,
    );
    if (source == null) {
      return _AttachmentPreparationResult(
        attachment: attachment,
        changed: false,
        missingSource: attachment.storedPaths.isNotEmpty,
      );
    }

    final sourcePath = source.$1;
    final sourceFile = source.$2;
    final isLegacySource = _isLegacyAttachmentFilePath(
      entryId: entryId,
      relativePath: sourcePath,
    );

    var changed = false;
    final obsoletePaths = <String>[];
    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    final targetPath = _attachmentMainPath(
      entryId: safeEntryId,
      attachmentId: attachment.id,
      extension: _extensionFromFileName(
        attachment.originalName.isEmpty ? sourcePath : attachment.originalName,
      ),
      originalName: attachment.originalName,
    );
    final targetFile = File(_resolveStoredPath(rootPath, targetPath));
    await targetFile.parent.create(recursive: true);

    if (sourcePath != targetPath || isLegacySource) {
      if (sourceFile.path != targetFile.path) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await sourceFile.copy(targetFile.path);
        if (_shouldDeleteOriginalAfterMove(rootPath, sourceFile.path)) {
          obsoletePaths.add(sourcePath);
        }
      }
      changed = true;
    }

    final nextAttachment = attachment.copyWith(path: targetPath);

    if (!changed && nextAttachment.path != attachment.path) {
      changed = true;
    }

    return _AttachmentPreparationResult(
      attachment: nextAttachment,
      changed: changed,
      missingSource: false,
      obsoletePaths: obsoletePaths,
    );
  }

  Future<DiaryAttachment> _normalizeAttachmentForEntry({
    required String entryId,
    required DiaryAttachment attachment,
  }) async {
    final rootDirectory = await _ensureRootDirectory();
    final entryDirectory = _entryAttachmentsDirectoryAt(
      rootDirectory.path,
      entryId,
    );
    if (!await entryDirectory.exists()) {
      await entryDirectory.create(recursive: true);
    }

    final path = await _normalizeLegacyAttachmentPathForEntry(
      rootPath: rootDirectory.path,
      entryId: entryId,
      attachment: attachment,
    );
    return attachment.copyWith(path: path);
  }

  Future<String> _normalizeLegacyAttachmentPathForEntry({
    required String rootPath,
    required String entryId,
    required DiaryAttachment attachment,
  }) async {
    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    final safeAttachmentId = _normalizeSafeStorageId(
      attachment.id,
      fallbackPrefix: 'att',
    );
    final extension = _extensionFromFileName(
      attachment.originalName.isEmpty
          ? attachment.path
          : attachment.originalName,
    );
    final sanitizedStem = _sanitizeFileName(
      _stemFromFileName(
        attachment.originalName.isEmpty
            ? attachment.id
            : attachment.originalName,
      ),
    );
    final targetFileName = sanitizedStem.isEmpty
        ? '$safeAttachmentId$extension'
        : '${safeAttachmentId}_$sanitizedStem$extension';
    final targetRelativePath =
        '$_attachmentsDirectoryName/$safeEntryId/$targetFileName';
    final targetFile = File(
      _join(rootPath, _attachmentsDirectoryName, safeEntryId, targetFileName),
    );
    final currentRelativePath = _safeStoredAttachmentPath(
      attachment.path,
      allowDrafts: true,
    );
    if (currentRelativePath == null) {
      return targetRelativePath;
    }
    final currentAbsolutePath = _resolveStoredPath(
      rootPath,
      currentRelativePath,
    );

    if (currentRelativePath == targetRelativePath &&
        await targetFile.exists()) {
      return targetRelativePath;
    }

    final sourceFile = File(currentAbsolutePath);
    if (await sourceFile.exists()) {
      if (sourceFile.path != targetFile.path) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await sourceFile.copy(targetFile.path);
        if (_shouldDeleteOriginalAfterMove(rootPath, sourceFile.path)) {
          await sourceFile.delete();
        }
      }
      return targetRelativePath;
    }

    final legacySource = await _findLegacyAttachmentSourceFile(
      rootPath: rootPath,
      entryId: safeEntryId,
      attachment: attachment,
      excludePath: currentRelativePath,
    );
    if (legacySource != null) {
      final sourceRelativePath = legacySource.$1;
      final sourceFile = legacySource.$2;
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await sourceFile.copy(targetFile.path);
      if (_shouldDeleteOriginalAfterMove(rootPath, sourceFile.path)) {
        await sourceFile.delete();
      }
      await _appendTombstones([sourceRelativePath]);
    }
    return targetRelativePath;
  }

  Future<(String, File)?> _findExistingAttachmentFile({
    required String rootPath,
    required DiaryAttachment attachment,
  }) async {
    final candidates = <String?>[
      attachment.path,
      ..._legacyAttachmentCandidates(
        entryId: _entryIdFromAttachmentPath(attachment.path),
        attachment: attachment,
      ),
    ];

    for (final candidate in candidates) {
      if (candidate == null || candidate.isEmpty) {
        continue;
      }
      final normalized = _safeStoredAttachmentPath(
        candidate,
        allowDrafts: true,
      );
      if (normalized == null) {
        continue;
      }
      final file = File(_resolveStoredPath(rootPath, normalized));
      if (await file.exists()) {
        return (normalized, file);
      }
    }
    return null;
  }

  Future<(String, File)?> _findLegacyAttachmentSourceFile({
    required String rootPath,
    required String entryId,
    required DiaryAttachment attachment,
    String? excludePath,
  }) async {
    final candidates = _legacyAttachmentCandidates(
      entryId: entryId,
      attachment: attachment,
    );
    for (final candidate in candidates) {
      if (candidate.isEmpty || candidate == excludePath) {
        continue;
      }
      final file = File(_resolveStoredPath(rootPath, candidate));
      if (await file.exists()) {
        return (candidate, file);
      }
    }
    return null;
  }

  List<String> _legacyAttachmentCandidates({
    required String? entryId,
    required DiaryAttachment attachment,
  }) {
    if (entryId == null || entryId.isEmpty) {
      return const [];
    }

    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    final safeAttachmentId = _normalizeSafeStorageId(
      attachment.id,
      fallbackPrefix: 'att',
    );
    final extension = _extensionFromFileName(
      attachment.originalName.isEmpty
          ? attachment.path
          : attachment.originalName,
    );

    return [
      '$_attachmentsDirectoryName/$safeEntryId/originals/$safeAttachmentId$extension',
      '$_attachmentsDirectoryName/$safeEntryId/previews/$safeAttachmentId.jpg',
      '$_attachmentsDirectoryName/$safeEntryId/thumbnails/$safeAttachmentId.jpg',
    ];
  }

  String? _entryIdFromAttachmentPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.length < 3 || parts.first != _attachmentsDirectoryName) {
      return null;
    }
    final candidate = parts[1];
    return SyncFilePolicy.isSafeId(candidate) ? candidate : null;
  }

  Future<void> _deleteObsoleteSyncFiles(
    String rootPath,
    List<String> relativePaths,
  ) async {
    for (final relativePath in relativePaths.toSet()) {
      final normalized = _safeStoredAttachmentPath(relativePath);
      if (normalized == null) {
        continue;
      }
      final file = File(_resolveStoredPath(rootPath, normalized));
      if (await file.exists()) {
        await file.delete();
      }
      await _deleteEmptyParentDirectories(
        rootPath: rootPath,
        relativePath: normalized,
      );
    }
  }

  Future<void> _deleteEmptyParentDirectories({
    required String rootPath,
    required String relativePath,
  }) async {
    final protectedDirectories = {
      _attachmentsDirectoryName,
      _entriesDirectoryName,
      _draftsDirectoryName,
      _cacheDirectoryName,
      _dustbinDirectoryName,
      _syncDirectoryName,
    };
    var normalized = relativePath.replaceAll('\\', '/');
    while (normalized.contains('/')) {
      normalized = normalized.substring(0, normalized.lastIndexOf('/'));
      if (protectedDirectories.contains(normalized)) {
        return;
      }
      final directory = Directory(
        _resolveProtectedSyncPath(rootPath, normalized),
      );
      if (!await directory.exists()) {
        continue;
      }
      if (await directory.list().isEmpty) {
        await directory.delete();
        continue;
      }
      return;
    }
  }

  bool _isLegacyAttachmentFilePath({
    required String entryId,
    required String relativePath,
  }) {
    final normalized = relativePath.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.length == 3 &&
        parts[0] == _attachmentsDirectoryName &&
        parts[1] == entryId;
  }

  String _attachmentMainPath({
    required String entryId,
    required String attachmentId,
    required String extension,
    required String originalName,
  }) {
    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    final safeAttachmentId = _normalizeSafeStorageId(
      attachmentId,
      fallbackPrefix: 'att',
    );
    final safeExtension = extension.isEmpty ? '.jpg' : extension;
    final safeStem = _sanitizeFileName(
      _stemFromFileName(originalName.isEmpty ? attachmentId : originalName),
    );
    final targetFileName = safeStem.isEmpty
        ? '$safeAttachmentId$safeExtension'
        : '${safeAttachmentId}_$safeStem$safeExtension';
    return '$_attachmentsDirectoryName/$safeEntryId/$targetFileName';
  }

  List<DiaryAttachment> _collectRemovedAttachments({
    required DiaryEntry? previousEntry,
    required DiaryEntry nextEntry,
  }) {
    if (previousEntry == null) {
      return const [];
    }

    final currentAttachmentIds = nextEntry.attachments
        .map((item) => item.id)
        .toSet();
    return previousEntry.attachments
        .where((attachment) => !currentAttachmentIds.contains(attachment.id))
        .toList();
  }

  List<DiaryAttachment> _collectRemovedDraftAttachments(
    List<DiaryAttachment> previous,
    List<DiaryAttachment> next,
  ) {
    final nextIds = next.map((attachment) => attachment.id).toSet();
    return previous
        .where((attachment) => !nextIds.contains(attachment.id))
        .toList();
  }

  Directory _entryAttachmentsDirectoryAt(String rootPath, String entryId) {
    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    return Directory(_join(rootPath, _attachmentsDirectoryName, safeEntryId));
  }

  Directory _dustbinAttachmentsDirectoryAt(String rootPath, String entryId) {
    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    return Directory(
      _join(
        rootPath,
        _dustbinDirectoryName,
        _dustbinAttachmentsDirectoryName,
        safeEntryId,
      ),
    );
  }

  Future<int> _deleteStaleTemporaryFiles(
    Directory rootDirectory,
    Duration maxAge,
  ) async {
    if (!await rootDirectory.exists()) {
      return 0;
    }

    final now = nowProvider();
    var deletedCount = 0;
    await for (final entity in rootDirectory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      if (!_isMaintenanceTemporaryFileName(name)) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (now.difference(stat.modified) < maxAge) {
          continue;
        }
        await entity.delete();
        deletedCount += 1;
      } catch (error) {
        AppLog.warn('清理临时文件失败: ${entity.path}; $error');
      }
    }
    return deletedCount;
  }

  bool _isMaintenanceTemporaryFileName(String fileName) {
    return fileName.endsWith('.tmp') || fileName.contains('.tmp.');
  }

  Future<int> _repairStaleIncompleteSyncStates(Duration maxAge) async {
    var repairedCount = 0;
    for (final provider in SyncProvider.values) {
      final state = await loadSyncState(provider);
      final startedAt = state.incompleteSyncStartedAt;
      if (startedAt == null) {
        continue;
      }
      if (nowProvider().difference(startedAt) < maxAge) {
        continue;
      }

      await saveSyncState(
        state.copyWith(
          lastKnownRemoteRevisions: const {},
          lastKnownRemoteNodes: const {},
          lastFailedAt: nowProvider(),
          lastFailureMessage: '检测到上次同步异常中断，已重置同步基线；下次同步会全量扫描重建。',
          clearLastKnownRemoteCursor: true,
          clearLastKnownRemoteRootId: true,
          clearIncompleteSync: true,
        ),
        provider,
      );
      repairedCount += 1;
    }
    return repairedCount;
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _writeJsonAtomically(File file, Object? value) async {
    await _writeStringAtomically(
      file,
      const JsonEncoder.withIndent('  ').convert(value),
    );
  }

  Future<void> _writeJsonCompactAtomically(File file, Object? value) async {
    await _writeStringAtomically(file, jsonEncode(value));
  }

  Future<Object?> _readJsonWithBackup(File file, String label) async {
    Object? primaryError;
    StackTrace? primaryStackTrace;
    try {
      return jsonDecode(await file.readAsString());
    } catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
      AppLog.warn('$label：读取主文件失败，将尝试备份 ${file.path}');
    }

    final backupFile = File('${file.path}$_backupFileSuffix');
    if (!await backupFile.exists()) {
      AppLog.error('$label：主文件损坏且没有可用备份', primaryError, primaryStackTrace);
      return null;
    }

    try {
      final raw = await backupFile.readAsString();
      final decoded = jsonDecode(raw);
      await _writeStringAtomically(file, raw, updateBackup: false);
      AppLog.warn('$label：已从备份恢复 ${file.path}');
      return decoded;
    } catch (error, stackTrace) {
      AppLog.error('$label：读取备份文件失败', error, stackTrace);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readJsonMapWithBackup(
    File file,
    String label,
  ) async {
    final raw = await _readJsonWithBackup(file, label);
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw != null) {
      AppLog.warn('$label：JSON 不是对象 ${file.path}');
    }
    return null;
  }

  Future<void> _writeStringAtomically(
    File file,
    String content, {
    bool updateBackup = true,
  }) async {
    await file.parent.create(recursive: true);
    String? existingContent;
    if (await file.exists()) {
      try {
        existingContent = await file.readAsString();
        if (existingContent == content) {
          return;
        }
      } catch (_) {
        AppLog.warn('读取文件内容失败，将重新写入: ${file.path}');
        // Fall through and rewrite the file if the current contents cannot be read.
      }
    }
    if (updateBackup && existingContent != null) {
      await _writeBackupStringAtomically(file, existingContent);
    }
    final temporaryFile = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporaryFile.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporaryFile.rename(file.path);
  }

  Future<void> _writeBackupStringAtomically(File file, String content) async {
    final backupFile = File('${file.path}$_backupFileSuffix');
    final temporaryBackupFile = File(
      '${backupFile.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporaryBackupFile.writeAsString(content, flush: true);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      await temporaryBackupFile.rename(backupFile.path);
    } catch (error, stackTrace) {
      AppLog.error('写入文件备份失败：${file.path}', error, stackTrace);
      if (await temporaryBackupFile.exists()) {
        await temporaryBackupFile.delete();
      }
    }
  }

  Future<String?> _readOneDriveSecret(String key) async {
    try {
      return await _secretStore.read(key);
    } catch (error) {
      AppLog.error('读取OneDrive密钥失败', error);
      return null;
    }
  }

  Future<void> _saveOneDriveSecrets({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secretStore.write(_oneDriveAccessTokenKey, accessToken);
    await _secretStore.write(_oneDriveRefreshTokenKey, refreshToken);
  }

  Future<void> _clearOneDriveSecrets() async {
    await _secretStore.delete(_oneDriveAccessTokenKey);
    await _secretStore.delete(_oneDriveRefreshTokenKey);
  }

  String _syncStateFileNameFor(SyncProvider provider) {
    switch (provider) {
      case SyncProvider.oneDrive:
        return _oneDriveSyncStateFileName;
    }
  }

  String _join(
    String first, [
    String? second,
    String? third,
    String? fourth,
    String? fifth,
  ]) {
    final segments = [first, ?second, ?third, ?fourth, ?fifth];
    return segments.join(Platform.pathSeparator);
  }

  bool _isJsonFile(String relativePath) {
    return relativePath.endsWith('.json');
  }

  ScheduleItem _normalizeSchedule(ScheduleItem schedule) {
    final title = ScheduleItem.normalizeTitle(schedule.title);
    final description = schedule.description?.trim();
    return schedule.copyWith(
      title: title,
      description: description == null || description.isEmpty
          ? null
          : description,
      clearDescription: description == null || description.isEmpty,
      date: DateTime(
        schedule.date.year,
        schedule.date.month,
        schedule.date.day,
      ),
    );
  }

  Future<String?> _loadLocalCurrentUserRole(Directory rootDirectory) async {
    final settingsFile = File(
      _join(rootDirectory.path, _localSettingsFileName),
    );
    if (!await settingsFile.exists()) {
      return null;
    }
    try {
      final jsonMap =
          jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
      return CoupleProfile.normalizeCurrentUserRole(
        jsonMap['current_user_role'] as String?,
      );
    } catch (error) {
      AppLog.error('加载本地用户角色失败', error);
      return null;
    }
  }

  Future<void> _saveLocalCurrentUserRole(
    Directory rootDirectory,
    String role,
  ) async {
    final settingsFile = File(
      _join(rootDirectory.path, _localSettingsFileName),
    );
    await _writeJsonAtomically(settingsFile, {
      'version': 1,
      'current_user_role': CoupleProfile.normalizeCurrentUserRole(role),
    });
  }

  String _toRelativePath(String rootPath, String filePath) {
    final normalizedRoot = rootPath.replaceAll('\\', '/').replaceAll('//', '/');
    final normalizedFile = filePath.replaceAll('\\', '/').replaceAll('//', '/');
    if (!normalizedFile.startsWith('$normalizedRoot/')) {
      return normalizedFile;
    }
    return normalizedFile.substring(normalizedRoot.length + 1);
  }

  String _entryRelativePath(String entryId) {
    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    return '$_entriesDirectoryName/$safeEntryId.json';
  }

  File _entryFileAt(String rootPath, String entryId) {
    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    return File(_join(rootPath, _entriesDirectoryName, '$safeEntryId.json'));
  }

  Future<void> _purgeDustbinIfNeeded() async {
    if (_hasPurgedDustbin) return;
    _hasPurgedDustbin = true;
    await purgeExpiredDustbinEntries();
  }

  Future<int> purgeExpiredDustbinEntries() async {
    _hasPurgedDustbin = true;
    final rootDirectory = await _ensureRootDirectory();
    final dustbinEntriesDirectory = Directory(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
      ),
    );
    if (!await dustbinEntriesDirectory.exists()) {
      return 0;
    }

    final files = await dustbinEntriesDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (files.isEmpty) {
      return 0;
    }

    final now = nowProvider();
    final expiredPaths = <String>[];
    var purgedEntries = 0;
    for (final file in files) {
      DeletedDiaryEntry deletedEntry;
      try {
        final fileName = file.uri.pathSegments.last;
        final trustedEntryId = fileName.endsWith('.json')
            ? fileName.substring(0, fileName.length - 5)
            : '';
        if (!SyncFilePolicy.isSafeId(trustedEntryId)) {
          continue;
        }
        final jsonMap =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawDeletedEntry = DeletedDiaryEntry.fromJson(jsonMap);
        deletedEntry = DeletedDiaryEntry(
          entry: await _sanitizeLoadedEntry(
            rootPath: rootDirectory.path,
            trustedEntryId: trustedEntryId,
            entry: rawDeletedEntry.entry,
          ),
          deletedAt: rawDeletedEntry.deletedAt,
        );
      } catch (error) {
        AppLog.error('清理过期回收站条目失败', error);
        continue;
      }
      if (now.isBefore(deletedEntry.deletedAt.add(_dustbinRetention))) {
        continue;
      }

      expiredPaths.add(_entryRelativePath(deletedEntry.entry.id));
      expiredPaths.addAll(
        deletedEntry.entry.attachments.expand(
          (attachment) => attachment.storedPaths,
        ),
      );
      await file.delete();
      await _deleteDirectoryIfExists(
        _dustbinAttachmentsDirectoryAt(
          rootDirectory.path,
          deletedEntry.entry.id,
        ),
      );
      purgedEntries += 1;
    }

    if (expiredPaths.isNotEmpty) {
      await _appendTombstones(expiredPaths);
    }
    return purgedEntries;
  }

  Future<void> _appendTombstones(List<String> rawPaths) async {
    final relativePaths = rawPaths
        .map(_safeSyncBusinessPathOrNull)
        .whereType<String>()
        .toSet();
    if (relativePaths.isEmpty) {
      return;
    }

    final existing = await loadTombstones();
    final tombstonesByPath = {
      for (final tombstone in existing) tombstone.relativePath: tombstone,
    };

    final now = DateTime.now();
    for (final path in relativePaths) {
      tombstonesByPath[path] = SyncTombstone(
        relativePath: path,
        deletedAt: now,
      );
    }

    final tombstones = tombstonesByPath.values.toList()
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    await saveTombstones(tombstones);
  }

  Future<void> _removeTombstones(List<String> rawPaths) async {
    final relativePaths = rawPaths
        .map(_safeSyncBusinessPathOrNull)
        .whereType<String>()
        .toSet();
    if (relativePaths.isEmpty) {
      return;
    }

    final tombstones = await loadTombstones();
    final filtered = tombstones
        .where((item) => !relativePaths.contains(item.relativePath))
        .toList();
    await saveTombstones(filtered);
  }

  Future<void> _moveEntryToDustbin(DiaryEntry entry) async {
    final rootDirectory = await _ensureRootDirectory();
    final safeEntryId = _normalizeSafeStorageId(
      entry.id,
      fallbackPrefix: 'entry',
    );
    final safeEntry = entry.id == safeEntryId
        ? entry
        : entry.copyWith(id: safeEntryId);
    final dustbinEntryFile = File(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
        '$safeEntryId.json',
      ),
    );
    await _writeJsonCompactAtomically(
      dustbinEntryFile,
      DeletedDiaryEntry(entry: safeEntry, deletedAt: nowProvider()).toJson(),
    );

    final sourceDirectory = _entryAttachmentsDirectoryAt(
      rootDirectory.path,
      safeEntryId,
    );
    final targetDirectory = _dustbinAttachmentsDirectoryAt(
      rootDirectory.path,
      safeEntryId,
    );
    if (await sourceDirectory.exists()) {
      await _deleteDirectoryIfExists(targetDirectory);
      await sourceDirectory.rename(targetDirectory.path);
    }
  }

  String _normalizeStoredPath(String storedPath) {
    final normalized = storedPath.replaceAll('\\', '/').trim();
    if (_isAbsolutePath(normalized)) {
      final attachmentsMarker = '/$_attachmentsDirectoryName/';
      final draftsMarker = '/$_draftsDirectoryName/';

      if (normalized.contains(attachmentsMarker)) {
        final index = normalized.indexOf(attachmentsMarker);
        return normalized.substring(index + 1);
      }
      if (normalized.contains(draftsMarker)) {
        final index = normalized.indexOf(draftsMarker);
        return normalized.substring(index + 1);
      }
      return normalized;
    }

    return normalized;
  }

  String _resolveStoredPath(String rootPath, String storedPath) {
    final normalizedPath = _normalizeStoredPath(storedPath);
    return _resolveProtectedSyncPath(rootPath, normalizedPath);
  }

  bool _isAbsolutePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(normalized);
  }

  String _normalizeProtectedRelativePath(
    String storedPath, {
    bool allowEmpty = true,
  }) {
    try {
      return SyncFilePolicy.normalizeRelativePath(
        storedPath,
        allowEmpty: allowEmpty,
      );
    } on FormatException catch (error) {
      throw FileSystemException(error.message, storedPath);
    }
  }

  String _normalizeSyncBusinessPath(String relativePath) {
    try {
      return SyncFilePolicy.normalizeSyncableBusinessPath(relativePath);
    } on FormatException catch (error) {
      throw FileSystemException(error.message, relativePath);
    }
  }

  String? _safeSyncBusinessPathOrNull(String relativePath) {
    try {
      return SyncFilePolicy.normalizeSyncableBusinessPath(
        _normalizeStoredPath(relativePath),
      );
    } on FormatException {
      return null;
    }
  }

  String _normalizeSafeStorageId(
    String rawId, {
    required String fallbackPrefix,
  }) {
    final trimmed = rawId.trim();
    if (SyncFilePolicy.isSafeId(trimmed)) {
      return trimmed;
    }
    final sanitized = _sanitizeFileName(trimmed);
    final bounded = sanitized.length > 96
        ? sanitized.substring(0, 96)
        : sanitized;
    if (SyncFilePolicy.isSafeId(bounded)) {
      return bounded;
    }
    return '${fallbackPrefix}_${nowProvider().microsecondsSinceEpoch}';
  }

  String? _safeStoredAttachmentPath(
    String? storedPath, {
    bool allowDrafts = false,
  }) {
    if (storedPath == null || storedPath.trim().isEmpty) {
      return null;
    }
    try {
      final normalized = _normalizeProtectedRelativePath(
        _normalizeStoredPath(storedPath),
        allowEmpty: false,
      );
      if (_isAttachmentStoragePath(normalized, allowDrafts: allowDrafts)) {
        return normalized;
      }
    } catch (error) {
      AppLog.warn('验证附件路径失败，已忽略不安全路径：$error');
      return null;
    }
    return null;
  }

  bool _isAttachmentStoragePath(
    String relativePath, {
    required bool allowDrafts,
  }) {
    if (relativePath.startsWith('$_attachmentsDirectoryName/') &&
        SyncFilePolicy.isSyncableBusinessPath(relativePath)) {
      return true;
    }
    if (!allowDrafts ||
        !relativePath.startsWith(
          '$_draftsDirectoryName/$_draftAttachmentsDirectoryName/',
        )) {
      return false;
    }
    final segments = relativePath.split('/');
    return segments.length >= 4 &&
        segments.every((segment) => segment.isNotEmpty) &&
        segments.skip(2).every((segment) => segment != '.' && segment != '..');
  }

  String _resolveProtectedSyncPath(String rootPath, String relativePath) {
    final normalizedRoot = p.normalize(p.absolute(rootPath));
    final safeRelativePath = _normalizeProtectedRelativePath(
      relativePath,
      allowEmpty: false,
    );
    final resolvedPath = p.normalize(
      p.join(normalizedRoot, p.joinAll(safeRelativePath.split('/'))),
    );
    if (!p.isWithin(normalizedRoot, resolvedPath)) {
      throw FileSystemException(
        'Sync path escaped storage root: $relativePath',
      );
    }
    return resolvedPath;
  }

  bool _shouldDeleteOriginalAfterMove(String rootPath, String sourcePath) {
    final normalizedRoot = rootPath.replaceAll('\\', '/');
    final normalizedSource = sourcePath.replaceAll('\\', '/');
    return normalizedSource.startsWith(normalizedRoot);
  }

  Future<String> _writeCompressedAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required String fileStem,
    required String sourceExtension,
    required int maxDimension,
    required int jpegQuality,
  }) async {
    final jpegFileName = '$fileStem.jpg';
    final jpegFile = File(_join(targetDirectory.path, jpegFileName));
    if (await _tryWriteResizedJpeg(
      sourceFile: sourceFile,
      targetFile: jpegFile,
      maxDimension: maxDimension,
      jpegQuality: jpegQuality,
    )) {
      return jpegFileName;
    }

    final pngFileName = '$fileStem.png';
    final pngFile = File(_join(targetDirectory.path, pngFileName));
    if (await _tryWriteResizedPng(
      sourceFile: sourceFile,
      targetFile: pngFile,
      maxDimension: maxDimension,
    )) {
      return pngFileName;
    }

    final fallbackExtension = _safeOriginalImageExtension(sourceExtension);
    final fallbackFileName = '$fileStem$fallbackExtension';
    final fallbackFile = File(_join(targetDirectory.path, fallbackFileName));
    await fallbackFile.parent.create(recursive: true);
    await sourceFile.copy(fallbackFile.path);
    AppLog.warn('图片压缩不可用，已保留原文件格式：$fallbackFileName');
    return fallbackFileName;
  }

  Future<bool> _tryWriteResizedJpeg({
    required File sourceFile,
    required File targetFile,
    required int maxDimension,
    required int jpegQuality,
  }) async {
    try {
      await targetFile.parent.create(recursive: true);
      final encoded = await _imageCodecChannel
          .invokeMethod<bool>('resizeToJpeg', {
            'sourcePath': sourceFile.path,
            'targetPath': targetFile.path,
            'maxDimension': maxDimension,
            'quality': jpegQuality,
          })
          .timeout(_imageTransformTimeout);
      return encoded == true && await targetFile.exists();
    } on MissingPluginException {
      return false;
    } catch (error) {
      AppLog.warn('JPEG 图片压缩不可用，将尝试 Flutter PNG 降级：$error');
      return false;
    }
  }

  Future<bool> _tryWriteResizedPng({
    required File sourceFile,
    required File targetFile,
    required int maxDimension,
  }) async {
    try {
      await targetFile.parent.create(recursive: true);
      final bytes = await sourceFile.readAsBytes().timeout(
        _imageTransformTimeout,
      );
      final codec = await ui
          .instantiateImageCodec(bytes, targetWidth: maxDimension)
          .timeout(_imageTransformTimeout);
      final frame = await codec.getNextFrame().timeout(_imageTransformTimeout);
      final byteData = await frame.image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(_imageTransformTimeout);
      if (byteData == null) {
        return false;
      }
      await targetFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      return true;
    } catch (error) {
      AppLog.warn('Flutter PNG 图片降级不可用，将保留原文件格式：$error');
      return false;
    }
  }

  String _safeOriginalImageExtension(String extension) {
    final normalized = extension.trim().toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(normalized)) {
      return normalized;
    }
    return '.jpg';
  }

  String _extensionFromFileName(String fileName) {
    final normalized = fileName.replaceAll('\\', '/');
    final lastSegment = normalized.split('/').last;
    if (!lastSegment.contains('.')) {
      return '.jpg';
    }
    return lastSegment.substring(lastSegment.lastIndexOf('.'));
  }

  String _stemFromFileName(String fileName) {
    final normalized = fileName.replaceAll('\\', '/');
    final lastSegment = normalized.split('/').last;
    if (!lastSegment.contains('.')) {
      return lastSegment;
    }
    return lastSegment.substring(0, lastSegment.lastIndexOf('.'));
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static CoupleProfile seedProfile() {
    return CoupleProfile(
      maleName: '他',
      femaleName: '她',
      togetherSince: DateTime(2025, 2, 6),
      isOnboarded: false,
    );
  }
}
