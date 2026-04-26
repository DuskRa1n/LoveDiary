import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_diary/app.dart';
import 'package:love_diary/data/diary_storage.dart';
import 'package:love_diary/models/diary_models.dart';
import 'package:love_diary/sync/onedrive/onedrive_models.dart';
import 'package:love_diary/sync/sync_models.dart';
import 'package:love_diary/sync/webdav/webdav_models.dart';
import 'package:love_diary/ui/real_timeline_tab.dart';

class FakeDiaryStorage extends DiaryStorage {
  FakeDiaryStorage({required CoupleProfile profile, List<DiaryEntry>? entries})
    : _profile = profile,
      _entries = List<DiaryEntry>.from(entries ?? const []);

  CoupleProfile _profile;
  List<DiaryEntry> _entries;
  DiaryDraft? _draft;

  @override
  Future<List<DiaryEntry>> loadEntries() async {
    return List<DiaryEntry>.from(_entries);
  }

  @override
  Future<void> saveEntries(List<DiaryEntry> entries) async {
    _entries = List<DiaryEntry>.from(entries);
  }

  @override
  Future<DiaryEntry> saveEntry(DiaryEntry entry) async {
    final index = _entries.indexWhere((item) => item.id == entry.id);
    if (index == -1) {
      _entries = [entry, ..._entries];
    } else {
      _entries[index] = entry;
    }
    return entry;
  }

  @override
  Future<void> deleteEntry(DiaryEntry entry) async {
    _entries = _entries.where((item) => item.id != entry.id).toList();
  }

  @override
  Future<CoupleProfile> loadProfile() async {
    return _profile;
  }

  @override
  Future<void> saveProfile(CoupleProfile profile) async {
    _profile = profile;
  }

  @override
  Future<DiaryDraft?> loadEntryDraft() async {
    return _draft;
  }

  @override
  Future<SyncState> loadSyncState() async {
    return SyncState.initial();
  }

  @override
  Future<OneDriveSyncConfig?> loadOneDriveSyncConfig() async {
    return null;
  }

  @override
  Future<WebDavSyncConfig?> loadWebDavSyncConfig() async {
    return null;
  }

  @override
  Future<void> saveEntryDraft(DiaryDraft draft) async {
    _draft = draft;
  }

  @override
  Future<void> clearEntryDraft() async {
    _draft = null;
  }

  @override
  Future<void> deleteAttachments(List<DiaryAttachment> attachments) async {}

  @override
  Future<Directory> ensureAttachmentsDirectory() async {
    return Directory.systemTemp;
  }

  @override
  Future<Directory> resolveRootDirectory() async {
    return Directory.systemTemp;
  }

  @override
  Future<DiaryAttachment> importAttachment({
    required String sourcePath,
    required String fileName,
    bool keepOriginal = false,
  }) async {
    return DiaryAttachment(
      id: 'att_${fileName.hashCode}',
      path: 'drafts/attachments/$fileName',
      originalName: fileName,
      createdAt: DateTime(2026, 4, 9, 12, 0),
    );
  }
}

void main() {
  Future<void> pumpApp(WidgetTester tester, DiaryStorage storage) async {
    await tester.pumpWidget(LoveDailyApp(storage: storage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('tapping an attachment opens the preview page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentGrid(
            attachments: [
              DiaryAttachment(
                id: 'att_preview',
                path: 'attachments/entry_preview/preview.jpg',
                originalName: 'preview.jpg',
                createdAt: DateTime(2026, 4, 9, 12, 0),
              ),
            ],
            rootDirectoryPath: null,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('preview.jpg'), findsOneWidget);
  });

  testWidgets('已引导状态会显示首页导航', (WidgetTester tester) async {
    final storage = FakeDiaryStorage(
      profile: CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
      entries: DiaryStorage.seedEntries(),
    );

    await pumpApp(tester, storage);

    expect(find.text('今天'), findsOneWidget);
    expect(find.text('回忆'), findsOneWidget);
    expect(find.text('我们'), findsOneWidget);
    expect(find.text('写日记'), findsOneWidget);
  });

  testWidgets('点击写日记会打开创建页', (WidgetTester tester) async {
    final storage = FakeDiaryStorage(
      profile: CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
      entries: DiaryStorage.seedEntries(),
    );

    await pumpApp(tester, storage);

    await tester.tap(find.text('写日记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('新建日记'), findsWidgets);
    expect(find.text('标题（可选）'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
    expect(find.text('状态'), findsOneWidget);
  });

  testWidgets('点击时间线日记会进入详情页', (WidgetTester tester) async {
    final storage = FakeDiaryStorage(
      profile: CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
      entries: DiaryStorage.seedEntries(),
    );

    await pumpApp(tester, storage);

    await tester.tap(find.text('回忆'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('深夜面馆'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('日记详情'), findsWidgets);
    expect(find.text('评论区'), findsOneWidget);
  });

  testWidgets('详情页可以进入编辑并保存更新', (WidgetTester tester) async {
    final storage = FakeDiaryStorage(
      profile: CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
      entries: DiaryStorage.seedEntries(),
    );

    await pumpApp(tester, storage);

    await tester.tap(find.text('回忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深夜面馆'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑日记'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '深夜面馆更新版');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('深夜面馆更新版'), findsWidgets);
  });

  testWidgets('详情页删除后会返回时间线并移除条目', (WidgetTester tester) async {
    final storage = FakeDiaryStorage(
      profile: CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
      entries: DiaryStorage.seedEntries(),
    );

    await pumpApp(tester, storage);

    await tester.tap(find.text('回忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深夜面馆'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除日记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('日记详情'), findsNothing);
    expect(find.text('深夜面馆'), findsNothing);
  });

  testWidgets('新建页未保存返回时会弹出处理对话框', (WidgetTester tester) async {
    final storage = FakeDiaryStorage(
      profile: CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
      entries: const [],
    );

    await pumpApp(tester, storage);

    await tester.tap(find.text('写日记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '这是还没保存的内容');
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.text('离开前要怎么处理？'), findsOneWidget);
    expect(find.text('存为草稿'), findsOneWidget);
  });

  testWidgets('时间线搜索会筛出匹配结果', (WidgetTester tester) async {
    final storage = FakeDiaryStorage(
      profile: CoupleProfile(
        maleName: '我',
        femaleName: '她',
        togetherSince: DateTime(2025, 2, 6),
        isOnboarded: true,
      ),
      entries: DiaryStorage.seedEntries(),
    );

    await pumpApp(tester, storage);

    await tester.tap(find.text('回忆'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '煎饼');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(RealTimelineTab),
        matching: find.text('周末煎饼计划'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('首次启动会显示资料引导', (WidgetTester tester) async {
    final storage = FakeDiaryStorage(profile: DiaryStorage.seedProfile());

    await pumpApp(tester, storage);

    expect(find.text('开始记录'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
