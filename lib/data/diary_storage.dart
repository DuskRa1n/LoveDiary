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
  static final SecretStore _defaultSecretStore = FlutterSecretStore();

  final String? rootDirectoryPath;
  final DateTime Function() nowProvider;
  final SecretStore? _secretStoreOverride;

  static const _profileFileName = 'profile.json';
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

    final entries = <DiaryEntry>[];
    for (final file in files) {
      try {
        final jsonMap =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        entries.add(DiaryEntry.fromJson(jsonMap));
      } catch (_) {
        continue;
      }
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<void> saveEntries(List<DiaryEntry> entries) async {
    final rootDirectory = await _ensureRootDirectory();
    final entriesDirectory = Directory(
      _join(rootDirectory.path, _entriesDirectoryName),
    );
    if (!await entriesDirectory.exists()) {
      await entriesDirectory.create(recursive: true);
    }

    final entryIds = entries.map((entry) => entry.id).toSet();
    for (final entry in entries) {
      final entryFile = File(
        _join(rootDirectory.path, _entriesDirectoryName, '${entry.id}.json'),
      );
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

    await _writeManifestCache(entries);
  }

  Future<DiaryEntry> saveEntry(DiaryEntry entry) async {
    final existingEntries = await loadEntries();
    final existingIndex = existingEntries.indexWhere(
      (item) => item.id == entry.id,
    );
    final previousEntry = existingIndex == -1
        ? null
        : existingEntries[existingIndex];
    final normalizedEntry = await _normalizeEntryForSave(entry);
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
    await saveEntries(entries);

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
    final entries = [
      for (final item in await loadEntries())
        if (item.id != entry.id) item,
    ];
    await saveEntries(entries);
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
        final jsonMap =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        deletedEntries.add(DeletedDiaryEntry.fromJson(jsonMap));
      } catch (_) {
        continue;
      }
    }
    deletedEntries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return deletedEntries;
  }

  Future<void> restoreDeletedEntry(DeletedDiaryEntry deletedEntry) async {
    final rootDirectory = await _ensureRootDirectory();
    final restoredEntry = deletedEntry.entry;
    final dustbinEntryFile = File(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
        '${restoredEntry.id}.json',
      ),
    );
    if (await dustbinEntryFile.exists()) {
      await dustbinEntryFile.delete();
    }

    final dustbinAttachmentsDirectory = _dustbinAttachmentsDirectoryAt(
      rootDirectory.path,
      restoredEntry.id,
    );
    final entryAttachmentsDirectory = _entryAttachmentsDirectoryAt(
      rootDirectory.path,
      restoredEntry.id,
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
    final dustbinEntryFile = File(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
        '${deletedEntry.entry.id}.json',
      ),
    );
    if (await dustbinEntryFile.exists()) {
      await dustbinEntryFile.delete();
    }

    await _deleteDirectoryIfExists(
      _dustbinAttachmentsDirectoryAt(rootDirectory.path, deletedEntry.entry.id),
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
    if (!await profileFile.exists()) {
      return seedProfile();
    }

    try {
      final jsonMap =
          jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
      return CoupleProfile.fromJson(jsonMap);
    } catch (_) {
      return seedProfile();
    }
  }

  Future<void> saveProfile(CoupleProfile profile) async {
    final rootDirectory = await _ensureRootDirectory();
    final profileFile = File(_join(rootDirectory.path, _profileFileName));
    await _writeJsonAtomically(profileFile, profile.toJson());
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

    final thumbnailFileName = '$fileStem.png';
    final previewFileName = '$fileStem.png';
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
    await _writeResizedPng(
      sourceFile: sourceFile,
      targetFile: thumbnailFile,
      maxDimension: 360,
    );
    await _writeResizedPng(
      sourceFile: sourceFile,
      targetFile: previewFile,
      maxDimension: 1600,
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
        final relativePath = _normalizeStoredPath(storedPath);
        if (_isAbsolutePath(relativePath)) {
          final absoluteFile = File(storedPath);
          if (await absoluteFile.exists()) {
            await absoluteFile.delete();
          }
          continue;
        }

        final file = File(_join(rootDirectory.path, relativePath));
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
    return _resolveProtectedSyncPath(rootDirectory.path, relativePath);
  }

  Future<void> deleteSyncFile(String relativePath) async {
    final rootDirectory = await _ensureRootDirectory();
    final normalizedPath = _normalizeStoredPath(relativePath);
    final protectedPath = _normalizeProtectedRelativePath(
      normalizedPath,
      allowEmpty: false,
    );

    final file = File(_resolveProtectedSyncPath(rootDirectory.path, protectedPath));
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
    final stateFile = File(_join(syncDirectory.path, _syncStateFileNameFor(provider)));
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
    final stateFile = File(_join(syncDirectory.path, _syncStateFileNameFor(provider)));
    await _writeJsonAtomically(stateFile, state.toJson());
  }

  Future<void> resetSyncState([
    SyncProvider provider = SyncProvider.oneDrive,
  ]) async {
    final syncDirectory = await ensureSyncDirectory();
    final stateFile = File(_join(syncDirectory.path, _syncStateFileNameFor(provider)));
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
        .map(_normalizeStoredPath)
        .map((path) => _normalizeProtectedRelativePath(path, allowEmpty: false))
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
      final accessToken = await _readOneDriveSecret(
        _oneDriveAccessTokenKey,
      ) ?? jsonMap['access_token'] as String?;
      final refreshToken = await _readOneDriveSecret(
        _oneDriveRefreshTokenKey,
      ) ?? jsonMap['refresh_token'] as String?;
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
      if (_isSyncMetadataFile(relativePath) ||
          _isDraftFile(relativePath) ||
          _isCacheFile(relativePath) ||
          _isDustbinFile(relativePath)) {
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
        final originalPath = attachment.originalPath;
        if (originalPath == null ||
            originalPath.isEmpty ||
            (attachment.previewPath == null &&
                attachment.thumbnailPath == null)) {
          attachments.add(attachment);
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

  Future<DiaryEntry> _normalizeEntryForSave(DiaryEntry entry) async {
    final normalizedAttachments = <DiaryAttachment>[];
    for (final attachment in entry.attachments) {
      normalizedAttachments.add(
        await _normalizeAttachmentForEntry(
          entryId: entry.id,
          attachment: attachment,
        ),
      );
    }

    return entry.copyWith(attachments: normalizedAttachments);
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
        extension: '.png',
      );
      await _writeResizedPng(
        sourceFile: sourceFile,
        targetFile: File(_resolveStoredPath(rootPath, targetPath)),
        maxDimension: 360,
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
        extension: '.png',
      );
      await _writeResizedPng(
        sourceFile: sourceFile,
        targetFile: File(_resolveStoredPath(rootPath, targetPath)),
        maxDimension: 1600,
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
        hasLocalOriginal: originalPath != null && attachment.hasLocalOriginal,
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
        ? '${attachment.id}$extension'
        : '${attachment.id}_$sanitizedStem$extension';
    final targetRelativePath =
        '$_attachmentsDirectoryName/$entryId/$targetFileName';
    final targetFile = File(
      _join(rootPath, _attachmentsDirectoryName, entryId, targetFileName),
    );
    final currentRelativePath = _normalizeStoredPath(attachment.path);
    final currentAbsolutePath = _resolveStoredPath(rootPath, attachment.path);

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

    final currentRelativePath = _normalizeStoredPath(sourcePath);

    final currentFileName = _fileNameFromPath(currentRelativePath);
    final extension = _extensionFromFileName(
      currentFileName.isEmpty ? fallbackExtension : currentFileName,
    );
    final targetFileName = '${attachment.id}$extension';
    final targetRelativePath =
        '$_attachmentsDirectoryName/$entryId/$role/$targetFileName';
    final targetFile = File(
      _join(rootPath, _attachmentsDirectoryName, entryId, role, targetFileName),
    );
    await targetFile.parent.create(recursive: true);

    if (currentRelativePath == targetRelativePath &&
        await targetFile.exists()) {
      return targetRelativePath;
    }

    final sourceFile = File(_resolveStoredPath(rootPath, sourcePath));
    if (!await sourceFile.exists()) {
      return sourcePath;
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
      final normalized = _normalizeStoredPath(candidate);
      final file = File(_resolveStoredPath(rootPath, normalized));
      if (await file.exists()) {
        return (normalized, file);
      }
    }
    return null;
  }

  Future<bool> _storedFileExists(String rootPath, String storedPath) async {
    final normalized = _normalizeStoredPath(storedPath);
    return File(_resolveStoredPath(rootPath, normalized)).exists();
  }

  Future<void> _deleteObsoleteSyncFiles(
    String rootPath,
    List<String> relativePaths,
  ) async {
    for (final relativePath in relativePaths.toSet()) {
      final normalized = _normalizeStoredPath(relativePath);
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
      final directory = Directory(_resolveStoredPath(rootPath, normalized));
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
    final safeExtension = extension.isEmpty ? '.jpg' : extension;
    return '$_attachmentsDirectoryName/$entryId/$role/$attachmentId$safeExtension';
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
    return Directory(_join(rootPath, _attachmentsDirectoryName, entryId));
  }

  Directory _dustbinAttachmentsDirectoryAt(String rootPath, String entryId) {
    return Directory(
      _join(
        rootPath,
        _dustbinDirectoryName,
        _dustbinAttachmentsDirectoryName,
        entryId,
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

  bool _isSyncMetadataFile(String relativePath) {
    return relativePath == '$_syncDirectoryName/$_syncStateFileName' ||
        relativePath == '$_syncDirectoryName/$_oneDriveSyncStateFileName' ||
        relativePath == '$_syncDirectoryName/$_tombstonesFileName' ||
        relativePath == '$_syncDirectoryName/$_oneDriveConfigFileName';
  }

  bool _isDraftFile(String relativePath) {
    return relativePath.startsWith('$_draftsDirectoryName/');
  }

  bool _isCacheFile(String relativePath) {
    return relativePath.startsWith('$_cacheDirectoryName/');
  }

  bool _isDustbinFile(String relativePath) {
    return relativePath.startsWith('$_dustbinDirectoryName/');
  }

  String _toRelativePath(String rootPath, String filePath) {
    final normalizedRoot = rootPath.replaceAll('\\', '/');
    final normalizedFile = filePath.replaceAll('\\', '/');
    final relative = normalizedFile.substring(normalizedRoot.length + 1);
    return relative;
  }

  String _entryRelativePath(String entryId) {
    return '$_entriesDirectoryName/$entryId.json';
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
        final jsonMap =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        deletedEntry = DeletedDiaryEntry.fromJson(jsonMap);
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
        .map(_normalizeStoredPath)
        .map((path) => _normalizeProtectedRelativePath(path))
        .where((path) => !_isDraftFile(path) && !_isCacheFile(path))
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
        .map(_normalizeStoredPath)
        .map((path) => _normalizeProtectedRelativePath(path))
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
    final dustbinEntryFile = File(
      _join(
        rootDirectory.path,
        _dustbinDirectoryName,
        _dustbinEntriesDirectoryName,
        '${entry.id}.json',
      ),
    );
    await _writeJsonAtomically(
      dustbinEntryFile,
      DeletedDiaryEntry(entry: entry, deletedAt: nowProvider()).toJson(),
    );

    final sourceDirectory = _entryAttachmentsDirectoryAt(
      rootDirectory.path,
      entry.id,
    );
    final targetDirectory = _dustbinAttachmentsDirectoryAt(
      rootDirectory.path,
      entry.id,
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
    final normalizedPath = storedPath.replaceAll('\\', '/');
    if (_isAbsolutePath(normalizedPath)) {
      return storedPath;
    }

    final normalizedRoot = rootPath.replaceAll('\\', '/');
    return '$normalizedRoot/$normalizedPath';
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
    final normalized = storedPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      if (allowEmpty) {
        return '';
      }
      throw const FileSystemException('Sync path must not be empty.');
    }
    if (_isAbsolutePath(normalized)) {
      throw FileSystemException('Refusing absolute sync path: $normalized');
    }

    final segments = normalized.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw FileSystemException('Refusing unsafe sync path: $normalized');
    }
    return segments.join('/');
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
