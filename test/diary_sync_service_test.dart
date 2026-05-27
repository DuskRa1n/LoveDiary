import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_diary/data/diary_storage.dart';
import 'package:love_diary/models/diary_models.dart';
import 'package:love_diary/sync/diary_sync_executor.dart';
import 'package:love_diary/sync/diary_sync_service.dart';
import 'package:love_diary/sync/sync_models.dart';
import 'package:love_diary/sync/sync_remote_source.dart';

import 'test_utils.dart';

class FakeRemoteSource implements DiarySyncRemoteSource {
  FakeRemoteSource(this.snapshot);

  final RemoteSyncSnapshot snapshot;

  @override
  Future<RemoteSyncSnapshot> fetchSnapshot({
    SyncState? baseline,
    SyncProgressCallback? onProgress,
    SyncCancellationCheck? checkCancelled,
  }) async {
    return snapshot;
  }

  @override
  Future<void> deleteFile(
    String relativePath, {
    SyncCancellationCheck? checkCancelled,
  }) async {}

  @override
  Future<void> downloadFile({
    required String relativePath,
    required String targetAbsolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  }) async {}

  @override
  Future<void> uploadFile({
    required String relativePath,
    required String absolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  }) async {}

  @override
  Future<void> persistSnapshot(List<LocalSyncFile> localFiles) async {}
}

class FailingUploadRemoteSource extends FakeRemoteSource {
  FailingUploadRemoteSource(super.snapshot);

  @override
  Future<void> uploadFile({
    required String relativePath,
    required String absolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  }) async {
    throw StateError('upload failed');
  }
}

class DelayedDownloadRemoteSource extends FakeRemoteSource {
  DelayedDownloadRemoteSource(super.snapshot);

  int activeDownloads = 0;
  int maxActiveDownloads = 0;

  @override
  Future<void> downloadFile({
    required String relativePath,
    required String targetAbsolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    activeDownloads++;
    if (activeDownloads > maxActiveDownloads) {
      maxActiveDownloads = activeDownloads;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      checkCancelled?.call();
      final file = File(targetAbsolutePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(relativePath);
    } finally {
      activeDownloads--;
    }
  }
}

class MemoryRemoteSource implements DiarySyncRemoteSource {
  final Map<String, RemoteSyncFile> _filesByPath = {};
  int _revisionCounter = 0;

  @override
  Future<RemoteSyncSnapshot> fetchSnapshot({
    SyncState? baseline,
    SyncProgressCallback? onProgress,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    return RemoteSyncSnapshot(
      cursor: 'memory_cursor_$_revisionCounter',
      files: _filesByPath.values.toList()
        ..sort((a, b) => a.relativePath.compareTo(b.relativePath)),
    );
  }

  @override
  Future<void> persistSnapshot(List<LocalSyncFile> localFiles) async {}

  @override
  Future<void> uploadFile({
    required String relativePath,
    required String absolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    final file = File(absolutePath);
    final stat = await file.stat();
    _revisionCounter++;
    _filesByPath[relativePath] = RemoteSyncFile(
      relativePath: relativePath,
      revision: 'rev_$_revisionCounter',
      fingerprint: '${stat.size}:${stat.modified.millisecondsSinceEpoch}',
      modifiedAt: stat.modified,
      size: stat.size,
      isBinary: isBinary,
    );
  }

  @override
  Future<void> downloadFile({
    required String relativePath,
    required String targetAbsolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteFile(
    String relativePath, {
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    _filesByPath.remove(relativePath);
  }
}

void main() {
  late Directory tempDirectory;
  late DiaryStorage storage;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('love_diary_sync_');
    storage = DiaryStorage(rootDirectoryPath: tempDirectory.path);
  });

  tearDown(() async {
    await deleteTempDirectory(tempDirectory);
  });

  test('uses remote baseline to delete remote when snapshot is empty', () async {
    final entry = DiaryEntry(
      id: 'entry_delete_with_empty_snapshot',
      author: '他',
      title: 'Delete using remote baseline',
      content:
          'Remote listing can be empty while the last sync still knows this file exists.',
      mood: 'happy',
      createdAt: DateTime(2026, 4, 9, 8, 30),
      comments: const [],
      attachments: const [],
    );
    await storage.saveEntry(entry);

    final localFile = (await storage.listSyncFiles()).singleWhere(
      (file) =>
          file.relativePath == 'entries/entry_delete_with_empty_snapshot.json',
    );

    await storage.saveSyncState(
      SyncState(
        lastSyncedAt: DateTime(2026, 4, 9, 9, 30),
        lastKnownRemoteCursor: 'cursor_1',
        lastKnownRemoteRootId: 'root_1',
        lastKnownLocalFingerprints: {
          'entries/entry_delete_with_empty_snapshot.json':
              localFile.fingerprint,
        },
        lastKnownRemoteRevisions: const {
          'entries/entry_delete_with_empty_snapshot.json': 'rev_delete_empty_1',
        },
        lastKnownRemoteNodes: {
          'root_1': const OneDriveRemoteNode(
            itemId: 'root_1',
            parentItemId: null,
            name: 'love_diary',
            isFolder: true,
            relativePath: '',
          ),
          'file_1': OneDriveRemoteNode(
            itemId: 'file_1',
            parentItemId: 'root_1',
            name: 'entry_delete_with_empty_snapshot.json',
            isFolder: false,
            relativePath: 'entries/entry_delete_with_empty_snapshot.json',
            revision: 'rev_delete_empty_1',
            fingerprint: localFile.fingerprint,
            modifiedAt: localFile.modifiedAt,
            size: localFile.size,
            isBinary: false,
          ),
        },
      ),
    );

    await storage.deleteEntry(entry);

    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        const RemoteSyncSnapshot(cursor: null, files: []),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();

    expect(plan.actions, hasLength(1));
    expect(plan.actions.single.type, SyncActionType.deleteRemote);
    expect(
      plan.actions.single.relativePath,
      'entries/entry_delete_with_empty_snapshot.json',
    );
    expect(plan.actions.single.reason, 'local_deleted_using_remote_baseline');
  });

  test(
    'ignores legacy cursor without a complete remote node baseline',
    () async {
      await storage.saveProfile(
        CoupleProfile(
          maleName: '我',
          femaleName: '她',
          togetherSince: DateTime(2025, 2, 6),
          isOnboarded: true,
        ),
      );

      final localFile = (await storage.listSyncFiles()).singleWhere(
        (file) => file.relativePath == 'profile.json',
      );
      await storage.saveSyncState(
        SyncState(
          lastSyncedAt: DateTime(2026, 4, 9, 9, 0),
          lastKnownRemoteCursor: 'legacy_cursor',
          lastKnownRemoteRootId: null,
          lastKnownLocalFingerprints: {'profile.json': localFile.fingerprint},
          lastKnownRemoteRevisions: const {'profile.json': 'legacy_remote_rev'},
        ),
      );

      final service = DiarySyncService(
        storage: storage,
        remoteSource: FakeRemoteSource(
          const RemoteSyncSnapshot(cursor: null, files: []),
        ),
        provider: SyncProvider.oneDrive,
      );

      final plan = await service.buildPlan();

      expect(plan.actions, hasLength(1));
      expect(plan.actions.single.type, SyncActionType.upload);
      expect(plan.actions.single.relativePath, 'profile.json');
    },
  );

  test('远端为空时会把本地文件标记为上传', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );
    await storage.saveEntries(DiaryStorage.seedEntries().take(1).toList());

    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        const RemoteSyncSnapshot(cursor: null, files: []),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();
    final uploadPaths = plan.actions
        .where((action) => action.type == SyncActionType.upload)
        .map((action) => action.relativePath)
        .toList();

    expect(uploadPaths, contains('profile.json'));
    expect(uploadPaths, contains('entries/entry_noodle_night.json'));
  });

  test('远端新增文件时会标记为下载', () async {
    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        RemoteSyncSnapshot(
          cursor: 'cursor_remote_1',
          files: [
            RemoteSyncFile(
              relativePath: 'entries/remote_only.json',
              revision: 'rev_remote_1',
              fingerprint: '100:1000',
              modifiedAt: DateTime(2026, 4, 9, 12, 0),
              size: 100,
              isBinary: false,
            ),
          ],
        ),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();

    expect(plan.actions, hasLength(1));
    expect(plan.actions.single.type, SyncActionType.download);
    expect(plan.actions.single.relativePath, 'entries/remote_only.json');
  });

  test('远端非业务文件不会进入同步计划', () async {
    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        RemoteSyncSnapshot(
          cursor: 'cursor_remote_noise',
          files: [
            RemoteSyncFile(
              relativePath: 'local_settings.json',
              revision: 'rev_local_settings',
              fingerprint: '1:1',
              modifiedAt: DateTime(2026, 4, 9, 12, 0),
              size: 1,
              isBinary: false,
            ),
            RemoteSyncFile(
              relativePath: 'sync/onedrive_state.json',
              revision: 'rev_sync_state',
              fingerprint: '1:1',
              modifiedAt: DateTime(2026, 4, 9, 12, 0),
              size: 1,
              isBinary: false,
            ),
            RemoteSyncFile(
              relativePath: 'drafts/entry_draft.json',
              revision: 'rev_draft',
              fingerprint: '1:1',
              modifiedAt: DateTime(2026, 4, 9, 12, 0),
              size: 1,
              isBinary: false,
            ),
            RemoteSyncFile(
              relativePath: 'entries/remote_only.json',
              revision: 'rev_remote_1',
              fingerprint: '100:1000',
              modifiedAt: DateTime(2026, 4, 9, 12, 0),
              size: 100,
              isBinary: false,
            ),
          ],
        ),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();
    final actionPaths = plan.actions
        .map((action) => action.relativePath)
        .toList();

    expect(actionPaths, ['entries/remote_only.json']);
  });

  test('首次同步同名同时间但指纹不同会标记冲突', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );
    final localFile = (await storage.listSyncFiles()).singleWhere(
      (file) => file.relativePath == 'profile.json',
    );

    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        RemoteSyncSnapshot(
          cursor: 'cursor_initial',
          files: [
            RemoteSyncFile(
              relativePath: 'profile.json',
              revision: 'rev_profile_remote',
              fingerprint: 'remote-content-hash',
              modifiedAt: localFile.modifiedAt,
              size: localFile.size,
              isBinary: localFile.isBinary,
            ),
          ],
        ),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();

    expect(plan.actions, hasLength(1));
    expect(plan.actions.single.type, SyncActionType.conflict);
    expect(
      plan.actions.single.reason,
      'initial_sync_unverified_same_timestamp',
    );
  });

  test('本地和远端都改过同一路径时会标记冲突', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );

    final localFiles = await storage.listSyncFiles();
    final profileFile = localFiles.singleWhere(
      (file) => file.relativePath == 'profile.json',
    );

    await storage.saveSyncState(
      SyncState(
        lastSyncedAt: null,
        lastKnownRemoteCursor: 'cursor_0',
        lastKnownRemoteRootId: 'root_profile',
        lastKnownLocalFingerprints: {'profile.json': 'old_local'},
        lastKnownRemoteRevisions: {'profile.json': 'old_remote'},
        lastKnownRemoteNodes: {
          'root_profile': OneDriveRemoteNode(
            itemId: 'root_profile',
            parentItemId: null,
            name: 'love_diary',
            isFolder: true,
            relativePath: '',
          ),
          'profile_file': OneDriveRemoteNode(
            itemId: 'profile_file',
            parentItemId: 'root_profile',
            name: 'profile.json',
            isFolder: false,
            relativePath: 'profile.json',
            revision: 'old_remote',
            fingerprint: 'old_remote',
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
            size: 0,
            isBinary: false,
          ),
        },
      ),
    );

    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        RemoteSyncSnapshot(
          cursor: 'cursor_1',
          files: [
            RemoteSyncFile(
              relativePath: 'profile.json',
              revision: 'new_remote',
              fingerprint: profileFile.fingerprint,
              modifiedAt: DateTime(2026, 4, 9, 11, 0),
              size: profileFile.size,
              isBinary: false,
            ),
          ],
        ),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();

    expect(plan.hasConflicts, isTrue);
    expect(plan.actions.single.type, SyncActionType.conflict);
    expect(plan.actions.single.relativePath, 'profile.json');
  });

  test('本地删除后会为远端生成删除动作', () async {
    final entry = DiaryEntry(
      id: 'entry_delete_sync',
      author: '他',
      title: '删除同步',
      content: '这篇会被删除。',
      mood: '安心',
      createdAt: DateTime(2026, 4, 9, 8, 0),
      comments: const [],
      attachments: const [],
    );
    await storage.saveEntry(entry);

    final localFile = (await storage.listSyncFiles()).singleWhere(
      (file) => file.relativePath == 'entries/entry_delete_sync.json',
    );

    await storage.saveSyncState(
      SyncState(
        lastSyncedAt: DateTime(2026, 4, 9, 9, 0),
        lastKnownRemoteCursor: 'cursor_0',
        lastKnownRemoteRootId: 'root_delete',
        lastKnownLocalFingerprints: {
          'entries/entry_delete_sync.json': localFile.fingerprint,
        },
        lastKnownRemoteRevisions: const {
          'entries/entry_delete_sync.json': 'rev_delete_1',
        },
        lastKnownRemoteNodes: {
          'root_delete': const OneDriveRemoteNode(
            itemId: 'root_delete',
            parentItemId: null,
            name: 'love_diary',
            isFolder: true,
            relativePath: '',
          ),
          'delete_file': OneDriveRemoteNode(
            itemId: 'delete_file',
            parentItemId: 'root_delete',
            name: 'entry_delete_sync.json',
            isFolder: false,
            relativePath: 'entries/entry_delete_sync.json',
            revision: 'rev_delete_1',
            fingerprint: localFile.fingerprint,
            modifiedAt: localFile.modifiedAt,
            size: localFile.size,
            isBinary: false,
          ),
        },
      ),
    );

    await storage.deleteEntry(entry);

    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        RemoteSyncSnapshot(
          cursor: 'cursor_2',
          files: [
            RemoteSyncFile(
              relativePath: 'entries/entry_delete_sync.json',
              revision: 'rev_delete_1',
              fingerprint: localFile.fingerprint,
              modifiedAt: DateTime(2026, 4, 9, 9, 0),
              size: localFile.size,
              isBinary: false,
            ),
          ],
        ),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();

    expect(plan.actions, hasLength(1));
    expect(plan.actions.single.type, SyncActionType.deleteRemote);
    expect(plan.actions.single.relativePath, 'entries/entry_delete_sync.json');
  });

  test('草稿不会混入正式同步计划', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );
    await storage.saveEntryDraft(
      DiaryDraft(
        title: '草稿',
        content: '先别同步这个',
        mood: '开心',
        selectedDate: DateTime(2026, 4, 9),
        attachments: const [],
        savedAt: DateTime(2026, 4, 9, 10, 0),
      ),
    );

    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        const RemoteSyncSnapshot(cursor: null, files: []),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();
    final actionPaths = plan.actions
        .map((action) => action.relativePath)
        .toList();

    expect(actionPaths, contains('profile.json'));
    expect(actionPaths.any((path) => path.startsWith('drafts/')), isFalse);
    expect(actionPaths.any((path) => path.startsWith('cache/')), isFalse);
  });

  test('incomplete sync marker disables stale baseline planning', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: 'me',
        femaleName: 'her',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );

    final localFile = (await storage.listSyncFiles()).singleWhere(
      (file) => file.relativePath == 'profile.json',
    );
    await storage.saveSyncState(
      SyncState(
        lastSyncedAt: DateTime(2026, 4, 9, 9, 0),
        lastKnownRemoteCursor: 'cursor_stale',
        lastKnownRemoteRootId: 'root_stale',
        lastKnownLocalFingerprints: {'profile.json': localFile.fingerprint},
        lastKnownRemoteRevisions: const {'profile.json': 'rev_stale'},
        lastKnownRemoteNodes: {
          'root_stale': const OneDriveRemoteNode(
            itemId: 'root_stale',
            parentItemId: null,
            name: 'love_diary',
            isFolder: true,
            relativePath: '',
          ),
          'profile_file': OneDriveRemoteNode(
            itemId: 'profile_file',
            parentItemId: 'root_stale',
            name: 'profile.json',
            isFolder: false,
            relativePath: 'profile.json',
            revision: 'rev_stale',
            fingerprint: localFile.fingerprint,
            modifiedAt: localFile.modifiedAt,
            size: localFile.size,
            isBinary: false,
          ),
        },
        incompleteSyncStartedAt: DateTime(2026, 4, 9, 9, 5),
        incompleteSyncActionCount: 3,
        incompleteSyncCompletedCount: 1,
        incompleteSyncLastPath: 'entries/previous.json',
      ),
    );

    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        const RemoteSyncSnapshot(cursor: null, files: []),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();

    expect(plan.actions, hasLength(1));
    expect(plan.actions.single.type, SyncActionType.upload);
    expect(plan.actions.single.relativePath, 'profile.json');
  });

  test('executor leaves checkpoint when a sync action fails', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: 'me',
        femaleName: 'her',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );

    final executor = DiarySyncExecutor(
      storage: storage,
      remoteSource: FailingUploadRemoteSource(
        const RemoteSyncSnapshot(cursor: null, files: []),
      ),
      provider: SyncProvider.oneDrive,
    );

    await expectLater(executor.sync(), throwsA(isA<StateError>()));

    final state = await storage.loadSyncState();
    expect(state.hasIncompleteSync, isTrue);
    expect(state.canUseDelta, isFalse);
    expect(state.incompleteSyncActionCount, 1);
    expect(state.incompleteSyncCompletedCount, 0);
  });

  test('cleans legacy derived attachment files from OneDrive', () async {
    final service = DiarySyncService(
      storage: storage,
      remoteSource: FakeRemoteSource(
        RemoteSyncSnapshot(
          cursor: 'cursor_legacy_attachment_cleanup',
          files: [
            RemoteSyncFile(
              relativePath: 'attachments/entry_1/previews/att_1.jpg',
              revision: 'rev_preview',
              fingerprint: '10:10',
              modifiedAt: DateTime(2026, 4, 9, 12, 0),
              size: 10,
              isBinary: true,
            ),
            RemoteSyncFile(
              relativePath: 'attachments/entry_1/thumbnails/att_1.jpg',
              revision: 'rev_thumb',
              fingerprint: '10:11',
              modifiedAt: DateTime(2026, 4, 9, 12, 0),
              size: 10,
              isBinary: true,
            ),
            RemoteSyncFile(
              relativePath: 'attachments/entry_1/att_1.jpg',
              revision: 'rev_current',
              fingerprint: '10:12',
              modifiedAt: DateTime(2026, 4, 9, 12, 0),
              size: 10,
              isBinary: true,
            ),
          ],
        ),
      ),
      provider: SyncProvider.oneDrive,
    );

    final plan = await service.buildPlan();
    final deleteRemotePaths = plan.actions
        .where((action) => action.type == SyncActionType.deleteRemote)
        .map((action) => action.relativePath)
        .toList();

    expect(
      deleteRemotePaths,
      contains('attachments/entry_1/previews/att_1.jpg'),
    );
    expect(
      deleteRemotePaths,
      contains('attachments/entry_1/thumbnails/att_1.jpg'),
    );
    expect(deleteRemotePaths, isNot(contains('attachments/entry_1/att_1.jpg')));
  });

  test('second sync does not re-upload unchanged json files', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: 'me',
        femaleName: 'her',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );
    await storage.saveEntries(DiaryStorage.seedEntries().take(1).toList());

    final remoteSource = MemoryRemoteSource();
    final firstExecutor = DiarySyncExecutor(
      storage: storage,
      remoteSource: remoteSource,
      provider: SyncProvider.oneDrive,
    );
    final firstResult = await firstExecutor.sync();
    expect(firstResult.uploadedPaths, isNotEmpty);

    final secondExecutor = DiarySyncExecutor(
      storage: storage,
      remoteSource: remoteSource,
      provider: SyncProvider.oneDrive,
    );
    final secondResult = await secondExecutor.sync();

    expect(secondResult.uploadedPaths, isEmpty);
    expect(secondResult.downloadedPaths, isEmpty);
    expect(secondResult.deletedRemotePaths, isEmpty);
    expect(secondResult.deletedLocalPaths, isEmpty);
    expect(secondResult.conflictPaths, isEmpty);
  });

  test('executor downloads files with bounded concurrency', () async {
    final remotePaths = [
      'profile.json',
      'entries/remote_1.json',
      'entries/remote_2.json',
      'entries/remote_3.json',
      'entries/remote_4.json',
    ];
    final remoteSource = DelayedDownloadRemoteSource(
      RemoteSyncSnapshot(
        cursor: 'cursor_downloads',
        files: [
          for (var index = 0; index < remotePaths.length; index++)
            RemoteSyncFile(
              relativePath: remotePaths[index],
              revision: 'rev_download_$index',
              fingerprint: 'remote_download_$index',
              modifiedAt: DateTime(2026, 4, 9, 12, index),
              size: remotePaths[index].length,
              isBinary: false,
            ),
        ],
      ),
    );

    final executor = DiarySyncExecutor(
      storage: storage,
      remoteSource: remoteSource,
      provider: SyncProvider.oneDrive,
    );
    final result = await executor.sync();

    expect(result.downloadedPaths, unorderedEquals(remotePaths));
    expect(remoteSource.maxActiveDownloads, greaterThan(1));
    expect(remoteSource.maxActiveDownloads, lessThanOrEqualTo(3));
    for (final path in remotePaths) {
      final absolutePath = await storage.resolveSyncFileAbsolutePath(path);
      expect(await File(absolutePath).exists(), isTrue);
    }
  });
}
