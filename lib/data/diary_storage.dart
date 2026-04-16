import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../models/diary_models.dart';
import '../sync/onedrive/onedrive_models.dart';
import '../sync/sync_models.dart';
import '../sync/webdav/webdav_models.dart';

class DiaryStorage {
  const DiaryStorage({
    this.rootDirectoryPath,
    this.nowProvider = DateTime.now,
  });

  static const MethodChannel _platformPathsChannel = MethodChannel(
    'love_diary/platform_paths',
  );

  final String? rootDirectoryPath;
  final DateTime Function() nowProvider;

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
  static const _tombstonesFileName = 'tombstones.json';
  static const _webDavConfigFileName = 'webdav_account.json';
  static const _oneDriveConfigFileName = 'onedrive_account.json';
  static const _dustbinRetention = Duration(days: 7);

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
        final jsonMap = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
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

    for (final entry in entries) {
      final entryFile = File(
        _join(rootDirectory.path, _entriesDirectoryName, '${entry.id}.json'),
      );
      final payload = const JsonEncoder.withIndent('  ').convert(entry.toJson());
      await entryFile.writeAsString(payload);
    }

    await _writeManifestCache(entries);
  }

  Future<DiaryEntry> saveEntry(DiaryEntry entry) async {
    final existingEntries = await loadEntries();
    final existingIndex = existingEntries.indexWhere((item) => item.id == entry.id);
    final previousEntry = existingIndex == -1 ? null : existingEntries[existingIndex];
    final normalizedEntry = await _normalizeEntryForSave(entry);
    final entries = existingIndex == -1
        ? [normalizedEntry, ...existingEntries]
        : [
            for (var index = 0; index < existingEntries.length; index++)
              if (index == existingIndex) normalizedEntry else existingEntries[index],
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
      ...normalizedEntry.attachments.map((attachment) => attachment.path),
    ]);
    if (removedAttachments.isNotEmpty) {
      await _appendTombstones(
        removedAttachments.map((attachment) => attachment.path).toList(),
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
        final jsonMap = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
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
      ...restoredEntry.attachments.map((attachment) => attachment.path),
    ]);
  }

  Future<void> permanentlyDeleteDeletedEntry(DeletedDiaryEntry deletedEntry) async {
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
      ...deletedEntry.entry.attachments.map((attachment) => attachment.path),
    ]);
  }

  Future<CoupleProfile> loadProfile() async {
    final rootDirectory = await _ensureRootDirectory();
    final profileFile = File(_join(rootDirectory.path, _profileFileName));
    if (!await profileFile.exists()) {
      return seedProfile();
    }

    try {
      final jsonMap = jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
      return CoupleProfile.fromJson(jsonMap);
    } catch (_) {
      return seedProfile();
    }
  }

  Future<void> saveProfile(CoupleProfile profile) async {
    final rootDirectory = await _ensureRootDirectory();
    final profileFile = File(_join(rootDirectory.path, _profileFileName));
    await profileFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(profile.toJson()),
    );
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
  }) async {
    final rootDirectory = await _ensureRootDirectory();
    final draftsDirectory = Directory(
      _join(
        rootDirectory.path,
        _draftsDirectoryName,
        _draftAttachmentsDirectoryName,
      ),
    );
    if (!await draftsDirectory.exists()) {
      await draftsDirectory.create(recursive: true);
    }

    final now = DateTime.now();
    final attachmentId = 'att_${now.microsecondsSinceEpoch}';
    final extension = _extensionFromFileName(fileName);
    final sanitizedStem = _sanitizeFileName(_stemFromFileName(fileName));
    final fileStem = sanitizedStem.isEmpty ? attachmentId : '${attachmentId}_$sanitizedStem';
    final targetFileName = '$fileStem$extension';
    final targetFile = File(_join(draftsDirectory.path, targetFileName));
    await File(sourcePath).copy(targetFile.path);

    return DiaryAttachment(
      id: attachmentId,
      path: '$_draftsDirectoryName/$_draftAttachmentsDirectoryName/$targetFileName',
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
      final relativePath = _normalizeStoredPath(attachment.path);
      if (relativePath == null || _isAbsolutePath(relativePath)) {
        final absoluteFile = File(attachment.path);
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

  Future<Directory> resolveRootDirectory() async {
    return _ensureRootDirectory();
  }

  Future<String> resolveSyncFileAbsolutePath(String relativePath) async {
    final rootDirectory = await _ensureRootDirectory();
    final normalizedRelativePath =
        relativePath.replaceAll('/', Platform.pathSeparator);
    return '${rootDirectory.path}${Platform.pathSeparator}$normalizedRelativePath';
  }

  Future<void> deleteSyncFile(String relativePath) async {
    final rootDirectory = await _ensureRootDirectory();
    final normalizedPath = _normalizeStoredPath(relativePath);
    if (normalizedPath == null) {
      return;
    }

    final file = File(_resolveStoredPath(rootDirectory.path, normalizedPath));
    if (await file.exists()) {
      await file.delete();
    }

    final lastSeparatorIndex = normalizedPath.lastIndexOf('/');
    if (lastSeparatorIndex != -1) {
      final directoryPath = normalizedPath.substring(0, lastSeparatorIndex);
      final directory = Directory(_join(rootDirectory.path, directoryPath));
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
    }

    await _removeTombstones([normalizedPath]);
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
      final jsonMap = jsonDecode(await draftFile.readAsString()) as Map<String, dynamic>;
      return DiaryDraft.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveEntryDraft(DiaryDraft draft) async {
    final rootDirectory = await _ensureRootDirectory();
    final draftsDirectory = Directory(_join(rootDirectory.path, _draftsDirectoryName));
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
    await draftFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(draft.toJson()),
    );
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

  Future<SyncState> loadSyncState() async {
    final syncDirectory = await ensureSyncDirectory();
    final stateFile = File(_join(syncDirectory.path, _syncStateFileName));
    if (!await stateFile.exists()) {
      return SyncState.initial();
    }

    try {
      final jsonMap = jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      return SyncState.fromJson(jsonMap);
    } catch (_) {
      return SyncState.initial();
    }
  }

  Future<void> saveSyncState(SyncState state) async {
    final syncDirectory = await ensureSyncDirectory();
    final stateFile = File(_join(syncDirectory.path, _syncStateFileName));
    await stateFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
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
          .map((item) => SyncTombstone.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveTombstones(List<SyncTombstone> tombstones) async {
    final syncDirectory = await ensureSyncDirectory();
    final tombstonesFile = File(_join(syncDirectory.path, _tombstonesFileName));
    await tombstonesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        tombstones.map((item) => item.toJson()).toList(),
      ),
    );
  }

  Future<WebDavSyncConfig?> loadWebDavSyncConfig() async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _webDavConfigFileName));
    if (!await configFile.exists()) {
      return null;
    }

    try {
      final jsonMap = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      return WebDavSyncConfig.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWebDavSyncConfig(WebDavSyncConfig config) async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _webDavConfigFileName));
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  Future<void> clearWebDavSyncConfig() async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _webDavConfigFileName));
    if (await configFile.exists()) {
      await configFile.delete();
    }
  }

  Future<OneDriveSyncConfig?> loadOneDriveSyncConfig() async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _oneDriveConfigFileName));
    if (!await configFile.exists()) {
      return null;
    }

    try {
      final jsonMap = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      return OneDriveSyncConfig.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveOneDriveSyncConfig(OneDriveSyncConfig config) async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _oneDriveConfigFileName));
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  Future<void> clearOneDriveSyncConfig() async {
    final syncDirectory = await ensureSyncDirectory();
    final configFile = File(_join(syncDirectory.path, _oneDriveConfigFileName));
    if (await configFile.exists()) {
      await configFile.delete();
    }
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

  Future<Directory> _ensureRootDirectory() async {
    final directory = rootDirectoryPath == null
        ? Directory(
            _join(
              (await _resolveApplicationDocumentsPath()),
              'love_diary',
            ),
          )
        : Directory(rootDirectoryPath!);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final entriesDirectory = Directory(_join(directory.path, _entriesDirectoryName));
    if (!await entriesDirectory.exists()) {
      await entriesDirectory.create(recursive: true);
    }

    final attachmentsDirectory = Directory(
      _join(directory.path, _attachmentsDirectoryName),
    );
    if (!await attachmentsDirectory.exists()) {
      await attachmentsDirectory.create(recursive: true);
    }

    final cacheDirectory = Directory(_join(directory.path, _cacheDirectoryName));
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }

    final draftsDirectory = Directory(_join(directory.path, _draftsDirectoryName));
    if (!await draftsDirectory.exists()) {
      await draftsDirectory.create(recursive: true);
    }

    final dustbinDirectory = Directory(_join(directory.path, _dustbinDirectoryName));
    if (!await dustbinDirectory.exists()) {
      await dustbinDirectory.create(recursive: true);
    }

    final dustbinEntriesDirectory = Directory(
      _join(directory.path, _dustbinDirectoryName, _dustbinEntriesDirectoryName),
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
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
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

  Future<DiaryAttachment> _normalizeAttachmentForEntry({
    required String entryId,
    required DiaryAttachment attachment,
  }) async {
    final rootDirectory = await _ensureRootDirectory();
    final entryDirectory = _entryAttachmentsDirectoryAt(rootDirectory.path, entryId);
    if (!await entryDirectory.exists()) {
      await entryDirectory.create(recursive: true);
    }

    final extension = _extensionFromFileName(attachment.originalName.isEmpty
        ? attachment.path
        : attachment.originalName);
    final sanitizedStem = _sanitizeFileName(
      _stemFromFileName(
        attachment.originalName.isEmpty ? attachment.id : attachment.originalName,
      ),
    );
    final targetFileName = sanitizedStem.isEmpty
        ? '${attachment.id}$extension'
        : '${attachment.id}_$sanitizedStem$extension';
    final targetRelativePath =
        '$_attachmentsDirectoryName/$entryId/$targetFileName';
    final targetFile = File(_join(entryDirectory.path, targetFileName));

    final currentRelativePath = _normalizeStoredPath(attachment.path);
    final currentAbsolutePath = _resolveStoredPath(rootDirectory.path, attachment.path);

    if (currentRelativePath == targetRelativePath && await targetFile.exists()) {
      return attachment.copyWith(path: targetRelativePath);
    }

    final sourceFile = File(currentAbsolutePath);
    if (await sourceFile.exists()) {
      if (sourceFile.path != targetFile.path) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await sourceFile.copy(targetFile.path);
        if (_shouldDeleteOriginalAfterMove(rootDirectory.path, sourceFile.path)) {
          await sourceFile.delete();
        }
      }
    }

    return attachment.copyWith(path: targetRelativePath);
  }

  List<DiaryAttachment> _collectRemovedAttachments({
    required DiaryEntry? previousEntry,
    required DiaryEntry nextEntry,
  }) {
    if (previousEntry == null) {
      return const [];
    }

    final currentAttachmentIds = nextEntry.attachments.map((item) => item.id).toSet();
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

  String _join(String first, [String? second, String? third, String? fourth]) {
    final segments = [
      first,
      if (second != null) second,
      if (third != null) third,
      if (fourth != null) fourth,
    ];
    return segments.join(Platform.pathSeparator);
  }

  bool _isJsonFile(String relativePath) {
    return relativePath.endsWith('.json');
  }

  bool _isSyncMetadataFile(String relativePath) {
    return relativePath == '$_syncDirectoryName/$_syncStateFileName' ||
        relativePath == '$_syncDirectoryName/$_tombstonesFileName' ||
        relativePath == '$_syncDirectoryName/$_webDavConfigFileName' ||
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
        final jsonMap = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        deletedEntry = DeletedDiaryEntry.fromJson(jsonMap);
      } catch (_) {
        continue;
      }
      if (now.isBefore(deletedEntry.deletedAt.add(_dustbinRetention))) {
        continue;
      }

      expiredPaths.add(_entryRelativePath(deletedEntry.entry.id));
      expiredPaths.addAll(
        deletedEntry.entry.attachments.map((attachment) => attachment.path),
      );
      await file.delete();
      await _deleteDirectoryIfExists(
        _dustbinAttachmentsDirectoryAt(rootDirectory.path, deletedEntry.entry.id),
      );
    }

    if (expiredPaths.isNotEmpty) {
      await _appendTombstones(expiredPaths);
    }
  }

  Future<void> _appendTombstones(List<String> rawPaths) async {
    final relativePaths = rawPaths
        .map(_normalizeStoredPath)
        .whereType<String>()
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
    final relativePaths = rawPaths.map(_normalizeStoredPath).whereType<String>().toSet();
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
    await dustbinEntryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        DeletedDiaryEntry(
          entry: entry,
          deletedAt: nowProvider(),
        ).toJson(),
      ),
    );

    final sourceDirectory = _entryAttachmentsDirectoryAt(rootDirectory.path, entry.id);
    final targetDirectory = _dustbinAttachmentsDirectoryAt(rootDirectory.path, entry.id);
    if (await sourceDirectory.exists()) {
      await _deleteDirectoryIfExists(targetDirectory);
      await sourceDirectory.rename(targetDirectory.path);
    }
  }

  String? _normalizeStoredPath(String storedPath) {
    final normalized = storedPath.replaceAll('\\', '/');
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
    return normalized.startsWith('/') || RegExp(r'^[a-zA-Z]:/').hasMatch(normalized);
  }

  bool _shouldDeleteOriginalAfterMove(String rootPath, String sourcePath) {
    final normalizedRoot = rootPath.replaceAll('\\', '/');
    final normalizedSource = sourcePath.replaceAll('\\', '/');
    return normalizedSource.startsWith(normalizedRoot);
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

  static List<DiaryEntry> seedEntries() {
    return [
      DiaryEntry(
        id: 'entry_noodle_night',
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
