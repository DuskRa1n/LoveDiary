import 'dart:io';

import 'package:love_diary/data/secret_store.dart';
import 'package:love_diary/models/diary_models.dart';

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

List<DiaryEntry> seedEntries() {
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

Future<void> deleteTempDirectory(Directory directory) async {
  const maxAttempts = 5;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (!await directory.exists()) {
      return;
    }

    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == maxAttempts - 1) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 60 * (attempt + 1)));
    }
  }
}
