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

class ImageCleanupResult {
  const ImageCleanupResult({
    required this.deletedOriginals,
    required this.freedBytes,
  });

  final int deletedOriginals;
  final int freedBytes;
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
  const DiaryStorage({
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
  static const _dustbinRetention = Duration(days: 7);
  static const _imageTransformTimeout = Duration(seconds: 20);
  static const _oneDriveAccessTokenKey = 'onedrive_access_token';
  static const _oneDriveRefreshTokenKey = 'onedrive_refresh_token';

  SecretStore get _secretStore => _secretStoreOverride ?? _defaultSecretStore;

  Future<List<DiaryEntry>> loadEntries() async {
    await purgeExpiredDustbinEntries();
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
      final jsonMap =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final entry = DiaryEntry.fromJson(jsonMap);
      final sanitizedEntry = await _sanitizeLoadedEntry(
        rootPath: rootPath,
        trustedEntryId: trustedEntryId,
        entry: entry,
      );
      if (jsonEncode(jsonMap) != jsonEncode(sanitizedEntry.toJson())) {
        await _writeJsonAtomically(file, sanitizedEntry.toJson());
      }
      return sanitizedEntry;
    } catch (_) {
      return null;
    }
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
    final existingEntries = await loadEntries();
    final existingIndex = existingEntries.indexWhere(
      (item) => item.id == safeEntry.id,
    );
    final previousEntry = existingIndex == -1
        ? null
        : existingEntries[existingIndex];
    final normalizedEntry = await _normalizeEntryForSave(safeEntry);
    final entries = existingIndex == -1
        ? [normalizedEntry, ...existingEntries]
        : [
            for (var index = 0; index < existingEntries.length; index++)
              if (index == existingIndex)
                normalizedEntry
              else
                existingEntries[index],
          ];

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final rootDirectory = await _ensureRootDirectory();
    await _writeJsonAtomically(
      _entryFileAt(rootDirectory.path, normalizedEntry.id),
      normalizedEntry.toJson(),
    );
    await _writeManifestCache(entries);

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
    final entries = [
      for (final item in await loadEntries())
        if (item.id != entry.id) item,
    ];
    await _writeManifestCache(entries);
    await _appendTombstones([
      _entryRelativePath(entry.id),
      ...entry.attachments.expand((attachment) => attachment.storedPaths),
    ]);
  }

  Future<List<DeletedDiaryEntry>> loadDustbinEntries() async {
    await purgeExpiredDustbinEntries();
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
      } catch (_) {
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

    final entries = [
      for (final item in await loadEntries())
        if (item.id != restoredEntry.id) item,
      restoredEntry,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await saveEntries(entries);
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
      final jsonMap =
          jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
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
    } catch (_) {
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
      final raw = jsonDecode(await schedulesFile.readAsString());
      final rawItems = raw is Map<String, dynamic>
          ? raw['items'] as List<dynamic>? ?? <dynamic>[]
          : raw as List<dynamic>? ?? <dynamic>[];
      final schedules = rawItems
          .map((item) => ScheduleItem.fromJson(item as Map<String, dynamic>))
          .where((item) => item.title.trim().isNotEmpty)
          .toList();
      schedules.sort(_compareSchedules);
      return schedules;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSchedules(List<ScheduleItem> schedules) async {
    final rootDirectory = await _ensureRootDirectory();
    final schedulesFile = File(_join(rootDirectory.path, _schedulesFileName));
    final normalizedSchedules = schedules.map(_normalizeSchedule).toList()
      ..sort(_compareSchedules);
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

    final thumbnailFileName = '$fileStem.jpg';
    final previewFileName = '$fileStem.jpg';
    final originalFileName = '$fileStem$extension';

    final thumbnailDirectory = Directory(
      _join(attachmentDraftDirectory.path, 'thumbnails'),
    );
    final previewDirectory = Directory(
      _join(attachmentDraftDirectory.path, 'previews'),
    );
    final originalDirectory = Directory(
      _join(attachmentDraftDirectory.path, 'originals'),
    );
    await thumbnailDirectory.create(recursive: true);
    await previewDirectory.create(recursive: true);
    if (keepOriginal) {
      await originalDirectory.create(recursive: true);
    }

    final thumbnailFile = File(
      _join(thumbnailDirectory.path, thumbnailFileName),
    );
    final previewFile = File(_join(previewDirectory.path, previewFileName));
    await _writeResizedPhoto(
      sourceFile: sourceFile,
      targetFile: thumbnailFile,
      maxDimension: 360,
      jpegQuality: 78,
    );
    await _writeResizedPhoto(
      sourceFile: sourceFile,
      targetFile: previewFile,
      maxDimension: 1600,
      jpegQuality: 86,
    );

    String? originalPath;
    if (keepOriginal) {
      final originalFile = File(
        _join(originalDirectory.path, originalFileName),
      );
      await sourceFile.copy(originalFile.path);
      originalPath =
          '$_draftsDirectoryName/$_draftAttachmentsDirectoryName/$attachmentId/originals/$originalFileName';
    }

    final thumbnailPath =
        '$_draftsDirectoryName/$_draftAttachmentsDirectoryName/$attachmentId/thumbnails/$thumbnailFileName';
    final previewPath =
        '$_draftsDirectoryName/$_draftAttachmentsDirectoryName/$attachmentId/previews/$previewFileName';

    return DiaryAttachment(
      id: attachmentId,
      path: previewPath,
      thumbnailPath: thumbnailPath,
      previewPath: previewPath,
      originalPath: originalPath,
      originalName: fileName,
      createdAt: now,
      hasLocalOriginal: keepOriginal,
      syncOriginal: keepOriginal,
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
      final jsonMap =
          jsonDecode(await draftFile.readAsString()) as Map<String, dynamic>;
      return DiaryDraft.fromJson(jsonMap);
    } catch (_) {
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
          final jsonMap =
              jsonDecode(await legacyFile.readAsString())
                  as Map<String, dynamic>;
          return SyncState.fromJson(jsonMap);
        } catch (_) {
          return SyncState.initial();
        }
      }
    }
    if (!await stateFile.exists()) {
      return SyncState.initial();
    }

    try {
      final jsonMap =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      return SyncState.fromJson(jsonMap);
    } catch (_) {
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
    await _writeJsonAtomically(stateFile, state.toJson());
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
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveTombstones(List<SyncTombstone> tombstones) async {
    final syncDirectory = await ensureSyncDirectory();
    final tombstonesFile = File(_join(syncDirectory.path, _tombstonesFileName));
    await _writeJsonAtomically(
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
      final jsonMap =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
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
        await _writeJsonAtomically(configFile, config.toStorageJson());
      }

      return config.copyWith(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } catch (_) {
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
    await _writeJsonAtomically(configFile, config.toStorageJson());
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
    await purgeExpiredDustbinEntries();
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
    final repaired = <DiaryEntry>[];

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
        repaired.add(entry.copyWith(attachments: attachments));
      } else {
        repaired.add(entry);
      }
    }

    if (repairedEntries > 0) {
      await saveEntries(repaired);
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

  Future<ImageCleanupResult> purgeLocalOriginals({
    Duration olderThan = const Duration(days: 30),
  }) async {
    final rootDirectory = await _ensureRootDirectory();
    final entries = await loadEntries();
    if (entries.isEmpty) {
      return const ImageCleanupResult(deletedOriginals: 0, freedBytes: 0);
    }

    final cutoff = nowProvider().subtract(olderThan);
    var changed = false;
    var deletedOriginals = 0;
    var freedBytes = 0;
    final updatedEntries = <DiaryEntry>[];

    for (final entry in entries) {
      var entryChanged = false;
      final attachments = <DiaryAttachment>[];
      for (final attachment in entry.attachments) {
        final originalPath = _safeStoredAttachmentPath(attachment.originalPath);
        if (originalPath == null ||
            originalPath.isEmpty ||
            (attachment.previewPath == null &&
                attachment.thumbnailPath == null)) {
          if (attachment.originalPath != originalPath ||
              attachment.hasLocalOriginal) {
            attachments.add(
              attachment.copyWith(
                clearOriginalPath: originalPath == null,
                originalPath: originalPath,
                hasLocalOriginal: false,
              ),
            );
            entryChanged = true;
            changed = true;
          } else {
            attachments.add(attachment);
          }
          continue;
        }

        final originalFile = File(
          _resolveStoredPath(rootDirectory.path, originalPath),
        );
        if (!await originalFile.exists()) {
          if (attachment.hasLocalOriginal) {
            attachments.add(attachment.copyWith(hasLocalOriginal: false));
            entryChanged = true;
            changed = true;
          } else {
            attachments.add(attachment);
          }
          continue;
        }

        final stat = await originalFile.stat();
        if (stat.modified.isAfter(cutoff)) {
          attachments.add(attachment);
          continue;
        }

        freedBytes += stat.size;
        await originalFile.delete();
        deletedOriginals += 1;
        entryChanged = true;
        changed = true;
        attachments.add(attachment.copyWith(hasLocalOriginal: false));
      }

      updatedEntries.add(
        entryChanged ? entry.copyWith(attachments: attachments) : entry,
      );
    }

    if (changed) {
      await saveEntries(updatedEntries);
    }

    return ImageCleanupResult(
      deletedOriginals: deletedOriginals,
      freedBytes: freedBytes,
    );
  }

  Future<Directory> _ensureRootDirectory() async {
    final directory = rootDirectoryPath == null
        ? Directory(
            _join((await _resolveApplicationDocumentsPath()), 'love_diary'),
          )
        : Directory(rootDirectoryPath!);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final entriesDirectory = Directory(
      _join(directory.path, _entriesDirectoryName),
    );
    if (!await entriesDirectory.exists()) {
      await entriesDirectory.create(recursive: true);
    }

    final attachmentsDirectory = Directory(
      _join(directory.path, _attachmentsDirectoryName),
    );
    if (!await attachmentsDirectory.exists()) {
      await attachmentsDirectory.create(recursive: true);
    }

    final cacheDirectory = Directory(
      _join(directory.path, _cacheDirectoryName),
    );
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }

    final draftsDirectory = Directory(
      _join(directory.path, _draftsDirectoryName),
    );
    if (!await draftsDirectory.exists()) {
      await draftsDirectory.create(recursive: true);
    }

    final dustbinDirectory = Directory(
      _join(directory.path, _dustbinDirectoryName),
    );
    if (!await dustbinDirectory.exists()) {
      await dustbinDirectory.create(recursive: true);
    }

    final dustbinEntriesDirectory = Directory(
      _join(
        directory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
      ),
    );
    if (!await dustbinEntriesDirectory.exists()) {
      await dustbinEntriesDirectory.create(recursive: true);
    }

    final dustbinAttachmentsDirectory = Directory(
      _join(
        directory.path,
        _dustbinDirectoryName,
        _dustbinAttachmentsDirectoryName,
      ),
    );
    if (!await dustbinAttachmentsDirectory.exists()) {
      await dustbinAttachmentsDirectory.create(recursive: true);
    }

    final syncDirectory = Directory(_join(directory.path, _syncDirectoryName));
    if (!await syncDirectory.exists()) {
      await syncDirectory.create(recursive: true);
    }

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
      } catch (_) {
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
    await _writeJsonAtomically(manifestFile, manifest);
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
    final thumbnailPath = _safeStoredAttachmentPath(
      attachment.thumbnailPath,
      allowDrafts: allowDrafts,
    );
    final previewPath = _safeStoredAttachmentPath(
      attachment.previewPath,
      allowDrafts: allowDrafts,
    );
    final originalPath = _safeStoredAttachmentPath(
      attachment.originalPath,
      allowDrafts: allowDrafts,
    );
    final path =
        _safeStoredAttachmentPath(attachment.path, allowDrafts: allowDrafts) ??
        previewPath ??
        thumbnailPath ??
        originalPath;

    if (path == null || path.isEmpty) {
      return null;
    }

    final hasLocalOriginal =
        originalPath != null && await _storedFileExists(rootPath, originalPath);
    return attachment.copyWith(
      id: attachmentId,
      path: path,
      thumbnailPath: thumbnailPath,
      previewPath: previewPath,
      originalPath: originalPath,
      clearThumbnailPath: thumbnailPath == null,
      clearPreviewPath: previewPath == null,
      clearOriginalPath: originalPath == null,
      hasLocalOriginal: hasLocalOriginal,
    );
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

    var thumbnailPath = attachment.thumbnailPath;
    var previewPath = attachment.previewPath;
    var originalPath = attachment.originalPath;
    var changed = false;
    final obsoletePaths = <String>[];

    if (thumbnailPath == null ||
        thumbnailPath.isEmpty ||
        !await _storedFileExists(rootPath, thumbnailPath)) {
      final targetPath = _attachmentRolePath(
        entryId: entryId,
        attachmentId: attachment.id,
        role: 'thumbnails',
        extension: '.jpg',
      );
      await _writeResizedPhoto(
        sourceFile: sourceFile,
        targetFile: File(_resolveStoredPath(rootPath, targetPath)),
        maxDimension: 360,
        jpegQuality: 78,
      );
      thumbnailPath = targetPath;
      changed = true;
    }

    if (previewPath == null ||
        previewPath.isEmpty ||
        !await _storedFileExists(rootPath, previewPath)) {
      final targetPath = _attachmentRolePath(
        entryId: entryId,
        attachmentId: attachment.id,
        role: 'previews',
        extension: '.jpg',
      );
      await _writeResizedPhoto(
        sourceFile: sourceFile,
        targetFile: File(_resolveStoredPath(rootPath, targetPath)),
        maxDimension: 1600,
        jpegQuality: 86,
      );
      previewPath = targetPath;
      changed = true;
    }

    if ((originalPath == null ||
            originalPath.isEmpty ||
            !await _storedFileExists(rootPath, originalPath)) &&
        isLegacySource) {
      final extension = _extensionFromFileName(
        attachment.originalName.isEmpty ? sourcePath : attachment.originalName,
      );
      final targetPath = _attachmentRolePath(
        entryId: entryId,
        attachmentId: attachment.id,
        role: 'originals',
        extension: extension,
      );
      final originalFile = File(_resolveStoredPath(rootPath, targetPath));
      await originalFile.parent.create(recursive: true);
      if (sourceFile.path != originalFile.path) {
        await sourceFile.copy(originalFile.path);
        if (_shouldDeleteOriginalAfterMove(rootPath, sourceFile.path)) {
          obsoletePaths.add(sourcePath);
        }
      }
      originalPath = targetPath;
      changed = true;
    }

    final nextPath = previewPath;
    final nextAttachment = attachment.copyWith(
      path: nextPath,
      thumbnailPath: thumbnailPath,
      previewPath: previewPath,
      originalPath: originalPath,
      hasLocalOriginal:
          originalPath != null &&
          originalPath.isNotEmpty &&
          await _storedFileExists(rootPath, originalPath),
      syncOriginal: attachment.syncOriginal,
    );

    if (!changed &&
        (nextAttachment.path != attachment.path ||
            nextAttachment.thumbnailPath != attachment.thumbnailPath ||
            nextAttachment.previewPath != attachment.previewPath ||
            nextAttachment.originalPath != attachment.originalPath ||
            nextAttachment.hasLocalOriginal != attachment.hasLocalOriginal)) {
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

    if (attachment.thumbnailPath != null ||
        attachment.previewPath != null ||
        attachment.originalPath != null) {
      final thumbnailPath = await _normalizeAttachmentPathForEntry(
        rootPath: rootDirectory.path,
        entryId: entryId,
        attachment: attachment,
        sourcePath: attachment.thumbnailPath,
        role: 'thumbnails',
        fallbackExtension: '.png',
      );
      final previewPath = await _normalizeAttachmentPathForEntry(
        rootPath: rootDirectory.path,
        entryId: entryId,
        attachment: attachment,
        sourcePath: attachment.previewPath,
        role: 'previews',
        fallbackExtension: '.png',
      );
      final originalPath = await _normalizeAttachmentPathForEntry(
        rootPath: rootDirectory.path,
        entryId: entryId,
        attachment: attachment,
        sourcePath: attachment.originalPath,
        role: 'originals',
        fallbackExtension: _extensionFromFileName(attachment.originalName),
      );
      final path =
          previewPath ??
          thumbnailPath ??
          originalPath ??
          await _normalizeLegacyAttachmentPathForEntry(
            rootPath: rootDirectory.path,
            entryId: entryId,
            attachment: attachment,
          );

      return attachment.copyWith(
        path: path,
        thumbnailPath: thumbnailPath,
        previewPath: previewPath,
        originalPath: originalPath,
        clearThumbnailPath: thumbnailPath == null,
        clearPreviewPath: previewPath == null,
        clearOriginalPath: originalPath == null,
        hasLocalOriginal:
            originalPath != null &&
            await _storedFileExists(rootDirectory.path, originalPath),
      );
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
    }
    return targetRelativePath;
  }

  Future<String?> _normalizeAttachmentPathForEntry({
    required String rootPath,
    required String entryId,
    required DiaryAttachment attachment,
    required String? sourcePath,
    required String role,
    required String fallbackExtension,
  }) async {
    if (sourcePath == null || sourcePath.isEmpty) {
      return null;
    }

    final currentRelativePath = _safeStoredAttachmentPath(
      sourcePath,
      allowDrafts: true,
    );
    if (currentRelativePath == null) {
      return null;
    }

    final currentFileName = _fileNameFromPath(currentRelativePath);
    final extension = _extensionFromFileName(
      currentFileName.isEmpty ? fallbackExtension : currentFileName,
    );
    final safeEntryId = _normalizeSafeStorageId(
      entryId,
      fallbackPrefix: 'entry',
    );
    final safeAttachmentId = _normalizeSafeStorageId(
      attachment.id,
      fallbackPrefix: 'att',
    );
    final targetFileName = '$safeAttachmentId$extension';
    final targetRelativePath =
        '$_attachmentsDirectoryName/$safeEntryId/$role/$targetFileName';
    final targetFile = File(
      _join(
        rootPath,
        _attachmentsDirectoryName,
        safeEntryId,
        role,
        targetFileName,
      ),
    );
    await targetFile.parent.create(recursive: true);

    if (currentRelativePath == targetRelativePath &&
        await targetFile.exists()) {
      return targetRelativePath;
    }

    final sourceFile = File(_resolveStoredPath(rootPath, currentRelativePath));
    if (!await sourceFile.exists()) {
      return currentRelativePath;
    }

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

  Future<(String, File)?> _findExistingAttachmentFile({
    required String rootPath,
    required DiaryAttachment attachment,
  }) async {
    final candidates = <String?>[
      attachment.originalPath,
      attachment.path,
      attachment.previewPath,
      attachment.thumbnailPath,
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

  Future<bool> _storedFileExists(String rootPath, String storedPath) async {
    final normalized = _safeStoredAttachmentPath(storedPath, allowDrafts: true);
    if (normalized == null) {
      return false;
    }
    return File(_resolveStoredPath(rootPath, normalized)).exists();
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

  String _attachmentRolePath({
    required String entryId,
    required String attachmentId,
    required String role,
    required String extension,
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
    return '$_attachmentsDirectoryName/$safeEntryId/$role/$safeAttachmentId$safeExtension';
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

  Future<void> _writeStringAtomically(File file, String content) async {
    await file.parent.create(recursive: true);
    final temporaryFile = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporaryFile.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporaryFile.rename(file.path);
  }

  Future<String?> _readOneDriveSecret(String key) async {
    try {
      return await _secretStore.read(key);
    } catch (_) {
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

  int _compareSchedules(ScheduleItem a, ScheduleItem b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) {
      return byDate;
    }
    return a.title.compareTo(b.title);
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
    } catch (_) {
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
    final normalizedRoot = rootPath.replaceAll('\\', '/');
    final normalizedFile = filePath.replaceAll('\\', '/');
    final relative = normalizedFile.substring(normalizedRoot.length + 1);
    return relative;
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

  Future<void> purgeExpiredDustbinEntries() async {
    final rootDirectory = await _ensureRootDirectory();
    final dustbinEntriesDirectory = Directory(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
      ),
    );
    if (!await dustbinEntriesDirectory.exists()) {
      return;
    }

    final files = await dustbinEntriesDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (files.isEmpty) {
      return;
    }

    final now = nowProvider();
    final expiredPaths = <String>[];
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
      } catch (_) {
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
    }

    if (expiredPaths.isNotEmpty) {
      await _appendTombstones(expiredPaths);
    }
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
    await _writeJsonAtomically(
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
    } catch (_) {
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

  Future<void> _writeResizedPhoto({
    required File sourceFile,
    required File targetFile,
    required int maxDimension,
    required int jpegQuality,
  }) async {
    if (await _tryWriteResizedJpeg(
      sourceFile: sourceFile,
      targetFile: targetFile,
      maxDimension: maxDimension,
      jpegQuality: jpegQuality,
    )) {
      return;
    }
    await _writeResizedPng(
      sourceFile: sourceFile,
      targetFile: targetFile,
      maxDimension: maxDimension,
    );
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
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeResizedPng({
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
        await sourceFile.copy(targetFile.path);
        return;
      }
      await targetFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    } catch (_) {
      await sourceFile.copy(targetFile.path);
    }
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

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  static CoupleProfile seedProfile() {
    return CoupleProfile(
      maleName: '他',
      femaleName: '她',
      togetherSince: DateTime(2025, 2, 6),
      isOnboarded: false,
    );
  }

  static List<DiaryEntry> seedEntries() {
    return [
      DiaryEntry(
        id: 'entry_noodle_night',
        author: '她',
        title: '深夜面馆',
        content: '晚上一起去吃了面，风有点凉，但你把围巾分给了我一半。回家路上还约好周末去看海。',
        mood: '开心',
        createdAt: DateTime(2026, 4, 2, 21, 18),
        comments: [
          DiaryComment(
            author: '她',
            content: '那天的牛肉面真的很好吃，下次还要去。',
            createdAt: DateTime(2026, 4, 2, 22, 3),
          ),
        ],
        attachments: const [],
      ),
      DiaryEntry(
        id: 'entry_rain_walk',
        author: '他',
        title: '下雨天一起散步',
        content: '原本只是想去便利店，结果下起小雨，我们干脆绕着小区走了一圈。你说这样的夜晚很安静。',
        mood: '治愈',
        createdAt: DateTime(2026, 3, 28, 20, 45),
        comments: [
          DiaryComment(
            author: '我',
            content: '回来的时候鞋子湿了，但心情很好。',
            createdAt: DateTime(2026, 3, 28, 21, 10),
          ),
        ],
        attachments: const [],
      ),
      DiaryEntry(
        id: 'entry_pancake_morning',
        author: '她',
        title: '周末煎饼计划',
        content: '早上一起做了煎饼，第一张糊掉了，第二张终于成功。你还认真摆盘，说要纪念第一次合作早餐。',
        mood: '甜',
        createdAt: DateTime(2026, 3, 16, 9, 32),
        comments: const [],
        attachments: const [],
      ),
    ];
  }
}
