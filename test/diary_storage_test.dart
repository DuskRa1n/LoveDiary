import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_diary/data/diary_storage.dart';
import 'package:love_diary/models/diary_models.dart';
import 'package:love_diary/sync/sync_models.dart';

void main() {
  late Directory tempDirectory;
  late DiaryStorage storage;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'love_diary_storage_',
    );
    storage = DiaryStorage(rootDirectoryPath: tempDirectory.path);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('会把资料和日记写入文件结构', () async {
    final profile = CoupleProfile(
      maleName: '男方',
      femaleName: '女方',
      togetherSince: DateTime(2025, 2, 6),
      isOnboarded: true,
    );
    final entries = [
      DiaryEntry(
        id: 'entry_test_1',
        author: '他',
        title: '一起逛超市',
        content: '买了很多零食，还讨论了周末要做什么。',
        mood: '开心',
        createdAt: DateTime(2026, 4, 8, 20, 30),
        comments: [
          DiaryComment(
            author: '她',
            content: '下次别再买那么多薯片了。',
            createdAt: DateTime(2026, 4, 8, 20, 40),
          ),
        ],
        attachments: [
          DiaryAttachment(
            id: 'att_photo_1',
            path: 'attachments/entry_test_1/att_photo_1_photo_1.jpg',
            originalName: 'photo_1.jpg',
            createdAt: DateTime(2026, 4, 8, 20, 41),
          ),
        ],
      ),
    ];

    await storage.saveProfile(profile);
    await storage.saveEntries(entries);

    expect(
      File(
        '${tempDirectory.path}${Platform.pathSeparator}profile.json',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${tempDirectory.path}${Platform.pathSeparator}cache${Platform.pathSeparator}manifest.json',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${tempDirectory.path}${Platform.pathSeparator}entries${Platform.pathSeparator}entry_test_1.json',
      ).existsSync(),
      isTrue,
    );

    final loadedProfile = await storage.loadProfile();
    final loadedEntries = await storage.loadEntries();

    expect(loadedProfile.maleName, '男方');
    expect(loadedProfile.femaleName, '女方');
    expect(loadedProfile.isOnboarded, isTrue);
    expect(loadedEntries, hasLength(1));
    expect(loadedEntries.first.title, '一起逛超市');
    expect(loadedEntries.first.comments.single.author, '她');
    expect(
      loadedEntries.first.attachments.single.path,
      'attachments/entry_test_1/att_photo_1_photo_1.jpg',
    );
  });

  test('会持久化同步状态和 tombstones', () async {
    final state = SyncState(
      lastSyncedAt: DateTime(2026, 4, 9, 10, 0),
      lastKnownRemoteCursor: 'cursor_001',
      lastKnownLocalFingerprints: const {'profile.json': '10:100'},
      lastKnownRemoteRevisions: const {'profile.json': 'rev_profile_1'},
    );
    final tombstones = [
      SyncTombstone(
        relativePath: 'entries/deleted_entry.json',
        deletedAt: DateTime(2026, 4, 9, 10, 30),
      ),
    ];

    await storage.saveSyncState(state);
    await storage.saveTombstones(tombstones);

    final loadedState = await storage.loadSyncState();
    final loadedTombstones = await storage.loadTombstones();

    expect(loadedState.lastKnownRemoteCursor, 'cursor_001');
    expect(
      loadedState.lastKnownRemoteRevisions['profile.json'],
      'rev_profile_1',
    );
    expect(loadedTombstones, hasLength(1));
    expect(loadedTombstones.single.relativePath, 'entries/deleted_entry.json');
  });

  test('会更新单篇日记并记录最后修改时间', () async {
    final entry = DiaryEntry(
      id: 'entry_update_1',
      author: '他',
      title: '第一次版本',
      content: '先记下今天的晚饭。',
      mood: '开心',
      createdAt: DateTime(2026, 4, 8, 20, 30),
      comments: const [],
      attachments: const [],
    );
    await storage.saveEntry(entry);

    final updatedEntry = entry.copyWith(
      title: '更新后的标题',
      content: '补上了散步和聊天的内容。',
      updatedAt: DateTime(2026, 4, 9, 9, 0),
    );
    await storage.saveEntry(updatedEntry);

    final loadedEntries = await storage.loadEntries();
    expect(loadedEntries, hasLength(1));
    expect(loadedEntries.single.title, '更新后的标题');
    expect(loadedEntries.single.updatedAt, DateTime(2026, 4, 9, 9, 0));
  });

  test('删除日记后会同步清理文件和 tombstone', () async {
    final entry = DiaryEntry(
      id: 'entry_delete_1',
      author: '他',
      title: '要删除的日记',
      content: '这篇会被移除。',
      mood: '想念',
      createdAt: DateTime(2026, 4, 8, 20, 30),
      comments: const [],
      attachments: const [],
    );
    await storage.saveEntry(entry);

    await storage.deleteEntry(entry);

    final loadedEntries = await storage.loadEntries();
    final tombstones = await storage.loadTombstones();
    final manifest = File(
      '${tempDirectory.path}${Platform.pathSeparator}cache${Platform.pathSeparator}manifest.json',
    ).readAsStringSync();

    expect(loadedEntries, isEmpty);
    expect(
      File(
        '${tempDirectory.path}${Platform.pathSeparator}entries${Platform.pathSeparator}entry_delete_1.json',
      ).existsSync(),
      isFalse,
    );
    final dustbinFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}dustbin${Platform.pathSeparator}entries${Platform.pathSeparator}entry_delete_1.json',
    );

    expect(manifest, contains('"entries": []'));
    expect(dustbinFile.existsSync(), isTrue);
    expect(
      tombstones.any(
        (item) => item.relativePath == 'entries/entry_delete_1.json',
      ),
      isFalse,
    );
  });

  test('草稿可保存读取并且不会进入正式同步文件列表', () async {
    final draft = DiaryDraft(
      title: '草稿标题',
      content: '还没写完。',
      mood: '安心',
      selectedDate: DateTime(2026, 4, 9),
      attachments: const [],
      savedAt: DateTime(2026, 4, 9, 11, 0),
    );

    await storage.saveEntryDraft(draft);
    final loadedDraft = await storage.loadEntryDraft();
    final files = await storage.listSyncFiles();

    expect(loadedDraft?.title, '草稿标题');
    expect(
      files.any((file) => file.relativePath == 'drafts/entry_draft.json'),
      isFalse,
    );

    await storage.clearEntryDraft();
    expect(await storage.loadEntryDraft(), isNull);
  });

  test('保存日记时会把临时附件整理到 entry 专属目录', () async {
    final sourceFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}source.jpg',
    );
    await sourceFile.writeAsBytes(List<int>.filled(8, 7));

    final importedAttachment = await storage.importAttachment(
      sourcePath: sourceFile.path,
      fileName: 'memory.jpg',
    );

    final entry = DiaryEntry(
      id: 'entry_with_attachment',
      author: '他',
      title: '带附件的日记',
      content: '测试附件分目录保存。',
      mood: '开心',
      createdAt: DateTime(2026, 4, 9, 12, 0),
      comments: const [],
      attachments: [importedAttachment],
    );

    final savedEntry = await storage.saveEntry(entry);

    expect(
      savedEntry.attachments.single.path,
      startsWith('attachments/entry_with_attachment/'),
    );
    expect(
      File(
        '${tempDirectory.path}${Platform.pathSeparator}${savedEntry.attachments.single.path.replaceAll('/', Platform.pathSeparator)}',
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'clearing draft after save keeps the finalized attachment file',
    () async {
      final sourceFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}draft_source.jpg',
      );
      await sourceFile.writeAsBytes(List<int>.filled(16, 3));

      final importedAttachment = await storage.importAttachment(
        sourcePath: sourceFile.path,
        fileName: 'scaled_36.png',
      );
      await storage.saveEntryDraft(
        DiaryDraft(
          title: 'draft title',
          content: 'draft content',
          mood: '开心',
          selectedDate: DateTime(2026, 4, 9),
          attachments: [importedAttachment],
          savedAt: DateTime(2026, 4, 9, 12, 0),
        ),
      );

      final savedEntry = await storage.saveEntry(
        DiaryEntry(
          id: 'entry_from_draft',
          author: '他',
          title: 'draft title',
          content: 'draft content',
          mood: '开心',
          createdAt: DateTime(2026, 4, 9, 12, 0),
          comments: const [],
          attachments: [importedAttachment],
        ),
      );

      await storage.clearEntryDraft();

      final attachmentPath = savedEntry.attachments.single.path.replaceAll(
        '/',
        Platform.pathSeparator,
      );
      final finalizedAttachment = File(
        '${tempDirectory.path}${Platform.pathSeparator}$attachmentPath',
      );

      expect(finalizedAttachment.existsSync(), isTrue);
      expect(await storage.loadEntryDraft(), isNull);
    },
  );

  test('会列出可用于网盘同步的文件清单', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: '男方',
        femaleName: '女方',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );
    await storage.saveEntries(DiaryStorage.seedEntries().take(1).toList());
    await storage.saveSyncState(SyncState.initial());
    await storage.saveTombstones(const []);

    final files = await storage.listSyncFiles();
    final relativePaths = files.map((file) => file.relativePath).toList();

    expect(relativePaths, contains('profile.json'));
    expect(relativePaths, isNot(contains('manifest.json')));
    expect(relativePaths, isNot(contains('cache/manifest.json')));
    expect(relativePaths, contains('entries/entry_noodle_night.json'));
    expect(relativePaths, isNot(contains('sync/state.json')));
    expect(relativePaths, isNot(contains('sync/tombstones.json')));
  });
  test(
    'purges expired dustbin entries after 7 days and creates tombstones',
    () async {
      final initialStorage = DiaryStorage(
        rootDirectoryPath: tempDirectory.path,
        nowProvider: () => DateTime(2026, 4, 9, 10, 0),
      );
      final entry = DiaryEntry(
        id: 'entry_dustbin_expired',
        author: '他',
        title: 'Dustbin expiry',
        content: 'Should stay in dustbin for seven days before true deletion.',
        mood: 'happy',
        createdAt: DateTime(2026, 4, 9, 9, 0),
        comments: const [],
        attachments: const [],
      );
      await initialStorage.saveEntry(entry);
      await initialStorage.deleteEntry(entry);

      final expiredStorage = DiaryStorage(
        rootDirectoryPath: tempDirectory.path,
        nowProvider: () => DateTime(2026, 4, 17, 10, 1),
      );
      await expiredStorage.purgeExpiredDustbinEntries();

      final tombstones = await expiredStorage.loadTombstones();
      final dustbinFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}dustbin${Platform.pathSeparator}entries${Platform.pathSeparator}entry_dustbin_expired.json',
      );

      expect(dustbinFile.existsSync(), isFalse);
      expect(
        tombstones.any(
          (item) => item.relativePath == 'entries/entry_dustbin_expired.json',
        ),
        isTrue,
      );
    },
  );
  test(
    'saving after a draft does not delete the final attachment file',
    () async {
      final sourceFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}source_keep.jpg',
      );
      await sourceFile.writeAsBytes(List<int>.filled(12, 5));

      final importedAttachment = await storage.importAttachment(
        sourcePath: sourceFile.path,
        fileName: 'keep.jpg',
      );

      await storage.saveEntryDraft(
        DiaryDraft(
          title: 'Draft with image',
          content: 'Temporary image should survive publish.',
          mood: '开心',
          selectedDate: DateTime(2026, 4, 9),
          attachments: [importedAttachment],
          savedAt: DateTime(2026, 4, 9, 12, 30),
        ),
      );

      final savedEntry = await storage.saveEntry(
        DiaryEntry(
          id: 'entry_keep_attachment',
          author: '他',
          title: 'Keep attachment',
          content: 'Final entry with image.',
          mood: '开心',
          createdAt: DateTime(2026, 4, 9, 12, 31),
          comments: const [],
          attachments: [importedAttachment],
        ),
      );
      await storage.clearEntryDraft();

      final savedAttachmentFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}${savedEntry.attachments.single.path.replaceAll('/', Platform.pathSeparator)}',
      );

      expect(savedAttachmentFile.existsSync(), isTrue);
    },
  );

  test('restoring a dustbin entry moves it back to active entries', () async {
    final sourceFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}restore_source.jpg',
    );
    await sourceFile.writeAsBytes(List<int>.filled(10, 2));

    final importedAttachment = await storage.importAttachment(
      sourcePath: sourceFile.path,
      fileName: 'restore.jpg',
    );
    final savedEntry = await storage.saveEntry(
      DiaryEntry(
        id: 'entry_restore',
        author: '他',
        title: 'Restore me',
        content: 'This entry should be restorable.',
        mood: '开心',
        createdAt: DateTime(2026, 4, 9, 13, 0),
        comments: const [],
        attachments: [importedAttachment],
      ),
    );

    await storage.deleteEntry(savedEntry);
    final dustbinEntries = await storage.loadDustbinEntries();
    await storage.restoreDeletedEntry(dustbinEntries.single);

    final restoredEntries = await storage.loadEntries();
    final restoredAttachmentFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}${savedEntry.attachments.single.path.replaceAll('/', Platform.pathSeparator)}',
    );

    expect(restoredEntries, hasLength(1));
    expect(restoredEntries.single.id, 'entry_restore');
    expect(restoredAttachmentFile.existsSync(), isTrue);
    expect(await storage.loadDustbinEntries(), isEmpty);
  });

  test('permanently deleting a dustbin entry appends tombstones', () async {
    final savedEntry = await storage.saveEntry(
      DiaryEntry(
        id: 'entry_purge_now',
        author: '他',
        title: 'Delete forever',
        content: 'This entry should be purged immediately.',
        mood: '开心',
        createdAt: DateTime(2026, 4, 9, 14, 0),
        comments: const [],
        attachments: const [],
      ),
    );

    await storage.deleteEntry(savedEntry);
    final dustbinEntries = await storage.loadDustbinEntries();
    await storage.permanentlyDeleteDeletedEntry(dustbinEntries.single);

    final tombstones = await storage.loadTombstones();

    expect(await storage.loadDustbinEntries(), isEmpty);
    expect(
      tombstones.any(
        (item) => item.relativePath == 'entries/entry_purge_now.json',
      ),
      isTrue,
    );
  });
}
