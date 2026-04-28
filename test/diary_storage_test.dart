import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_diary/data/diary_storage.dart';
import 'package:love_diary/data/secret_store.dart';
import 'package:love_diary/models/diary_models.dart';
import 'package:love_diary/sync/onedrive/onedrive_models.dart';
import 'package:love_diary/sync/sync_models.dart';

class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

final List<int> _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0n0AAAAASUVORK5CYII=',
);

void main() {
  late Directory tempDirectory;
  late DiaryStorage storage;
  late MemorySecretStore secretStore;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'love_diary_storage_',
    );
    secretStore = MemorySecretStore();
    storage = DiaryStorage(
      rootDirectoryPath: tempDirectory.path,
      secretStore: secretStore,
    );
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

  test('本机视角不会写入可同步的 profile.json', () async {
    await storage.saveProfile(
      CoupleProfile(
        maleName: '男方',
        femaleName: '女方',
        currentUserRole: 'female',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
    );

    final profileFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}profile.json',
    );
    final localSettingsFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}local_settings.json',
    );
    final profileJson =
        jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
    final localJson =
        jsonDecode(await localSettingsFile.readAsString())
            as Map<String, dynamic>;

    expect(profileJson.containsKey('current_user_role'), isFalse);
    expect(localJson['current_user_role'], 'female');
    expect((await storage.loadProfile()).currentUserRole, 'female');

    final relativePaths = (await storage.listSyncFiles())
        .map((file) => file.relativePath)
        .toList();
    expect(relativePaths, contains('profile.json'));
    expect(relativePaths, isNot(contains('local_settings.json')));
  });

  test('旧版 profile 中的视角会迁移成本机私有设置', () async {
    final profileFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}profile.json',
    );
    await profileFile.writeAsString(
      jsonEncode({
        'male_name': '男方',
        'female_name': '女方',
        'current_user_role': 'female',
        'together_since': DateTime(2025, 2, 6).toIso8601String(),
        'is_onboarded': true,
      }),
    );

    final loadedProfile = await storage.loadProfile();
    final sanitizedProfileJson =
        jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
    final localSettingsFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}local_settings.json',
    );
    final localJson =
        jsonDecode(await localSettingsFile.readAsString())
            as Map<String, dynamic>;

    expect(loadedProfile.currentUserRole, 'female');
    expect(sanitizedProfileJson.containsKey('current_user_role'), isFalse);
    expect(localJson['current_user_role'], 'female');
  });

  test('会保存、读取和删除日程', () async {
    final schedule = ScheduleItem(
      id: 'schedule_birthday',
      title: '他的生日',
      description: '准备礼物',
      date: DateTime(2026, 5, 7),
      type: ScheduleItemType.yearly,
      createdAt: DateTime(2026, 4, 28, 12, 0),
    );

    final savedSchedule = await storage.saveSchedule(schedule);
    final loadedSchedules = await storage.loadSchedules();

    expect(savedSchedule.title, '他的生日');
    expect(
      File(
        '${tempDirectory.path}${Platform.pathSeparator}schedules.json',
      ).existsSync(),
      isTrue,
    );
    expect(loadedSchedules, hasLength(1));
    expect(loadedSchedules.single.type, ScheduleItemType.yearly);
    expect(loadedSchedules.single.description, '准备礼物');

    await storage.deleteSchedule(schedule);
    expect(await storage.loadSchedules(), isEmpty);
  });

  test('日程标题不能超过 8 个字', () async {
    final schedule = ScheduleItem(
      id: 'schedule_long_title',
      title: '这是一个过长的日程标题',
      date: DateTime(2026, 5, 7),
      type: ScheduleItemType.oneTime,
      createdAt: DateTime(2026, 4, 28, 12, 0),
    );

    await expectLater(storage.saveSchedule(schedule), throwsFormatException);
  });

  test('会持久化同步状态和 tombstones', () async {
    final state = SyncState(
      lastSyncedAt: DateTime(2026, 4, 9, 10, 0),
      lastKnownRemoteCursor: 'cursor_001',
      lastKnownRemoteRootId: 'root_001',
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
    expect(loadedState.lastKnownRemoteRootId, 'root_001');
    expect(
      loadedState.lastKnownRemoteRevisions['profile.json'],
      'rev_profile_1',
    );
    expect(loadedTombstones, hasLength(1));
    expect(loadedTombstones.single.relativePath, 'entries/deleted_entry.json');
  });

  test('OneDrive 凭据会写入安全存储而不是配置文件', () async {
    await storage.saveOneDriveSyncConfig(
      OneDriveSyncConfig(
        clientId: 'client',
        tenant: 'common',
        remoteFolder: 'love_diary',
        accessToken: 'access_token_secret',
        refreshToken: 'refresh_token_secret',
        expiresAt: DateTime(2026, 4, 9, 12, 0),
        accountName: 'Eric',
        accountEmail: 'eric@example.com',
      ),
    );

    final syncDirectory = await storage.ensureSyncDirectory();
    final configFile = File(
      '${syncDirectory.path}${Platform.pathSeparator}onedrive_account.json',
    );
    final configJson =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final loadedConfig = await storage.loadOneDriveSyncConfig();

    expect(configJson.containsKey('access_token'), isFalse);
    expect(configJson.containsKey('refresh_token'), isFalse);
    expect(
      await secretStore.read('onedrive_access_token'),
      'access_token_secret',
    );
    expect(
      await secretStore.read('onedrive_refresh_token'),
      'refresh_token_secret',
    );
    expect(loadedConfig?.accessToken, 'access_token_secret');
    expect(loadedConfig?.refreshToken, 'refresh_token_secret');
  });

  test('旧版明文 OneDrive 凭据会在读取时迁移到安全存储', () async {
    final syncDirectory = await storage.ensureSyncDirectory();
    final configFile = File(
      '${syncDirectory.path}${Platform.pathSeparator}onedrive_account.json',
    );
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'client_id': 'client',
        'tenant': 'common',
        'remote_folder': 'love_diary',
        'access_token': 'legacy_access',
        'refresh_token': 'legacy_refresh',
        'expires_at': '2026-04-09T12:00:00.000',
        'sync_on_write': true,
        'minimum_sync_interval_minutes': 0,
        'max_destructive_actions': 3,
        'sync_originals': false,
        'download_originals': false,
        'local_original_retention_days': 30,
      }),
    );

    final loadedConfig = await storage.loadOneDriveSyncConfig();
    final rewrittenJson =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;

    expect(loadedConfig?.accessToken, 'legacy_access');
    expect(loadedConfig?.refreshToken, 'legacy_refresh');
    expect(await secretStore.read('onedrive_access_token'), 'legacy_access');
    expect(await secretStore.read('onedrive_refresh_token'), 'legacy_refresh');
    expect(rewrittenJson.containsKey('access_token'), isFalse);
    expect(rewrittenJson.containsKey('refresh_token'), isFalse);
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
      isTrue,
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
    await sourceFile.writeAsBytes(_tinyPngBytes);

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
      await sourceFile.writeAsBytes(_tinyPngBytes);

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
    expect(relativePaths, isNot(contains('sync/onedrive_state.json')));
    expect(relativePaths, isNot(contains('sync/tombstones.json')));
  });

  test('拒绝越界的远端同步路径', () async {
    await expectLater(
      storage.resolveSyncFileAbsolutePath('../profile.json'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      storage.resolveSyncFileAbsolutePath('entries//bad.json'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      storage.resolveSyncFileAbsolutePath('local_settings.json'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('远端日记 JSON 内部的危险 id 和附件路径会被清理', () async {
    final entriesDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}entries',
    );
    await entriesDirectory.create(recursive: true);
    final entryFile = File(
      '${entriesDirectory.path}${Platform.pathSeparator}entry_safe.json',
    );
    await entryFile.writeAsString(
      jsonEncode({
        'id': '../profile',
        'author': '他',
        'title': '远端坏数据',
        'content': '这条数据的内部路径不可信。',
        'mood': '警觉',
        'created_at': DateTime(2026, 4, 9, 10, 0).toIso8601String(),
        'comments': [],
        'attachments': [
          {
            'id': '../evil',
            'path': '../profile.json',
            'original_name': 'evil.jpg',
            'created_at': DateTime(2026, 4, 9, 10, 1).toIso8601String(),
            'has_local_original': true,
          },
          {
            'id': 'att_safe',
            'path': 'attachments/entry_safe/previews/att_safe.png',
            'original_path': 'attachments/entry_safe/originals/att_safe.jpg',
            'original_name': 'safe.jpg',
            'created_at': DateTime(2026, 4, 9, 10, 2).toIso8601String(),
            'has_local_original': true,
          },
        ],
      }),
    );

    final entries = await storage.loadEntries();
    final rewrittenJson =
        jsonDecode(await entryFile.readAsString()) as Map<String, dynamic>;
    final rewrittenAttachments = rewrittenJson['attachments'] as List<dynamic>;

    expect(entries, hasLength(1));
    expect(entries.single.id, 'entry_safe');
    expect(entries.single.attachments, hasLength(1));
    expect(entries.single.attachments.single.id, 'att_safe');
    expect(entries.single.attachments.single.hasLocalOriginal, isFalse);
    expect(rewrittenJson['id'], 'entry_safe');
    expect(
      (rewrittenAttachments.single as Map<String, dynamic>).containsKey(
        'has_local_original',
      ),
      isFalse,
    );
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
      await sourceFile.writeAsBytes(_tinyPngBytes);

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
    await sourceFile.writeAsBytes(_tinyPngBytes);

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
