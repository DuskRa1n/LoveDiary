import '../utils/app_log.dart';

class DiaryComment {
  const DiaryComment({
    required this.author,
    required this.content,
    required this.createdAt,
  });

  final String author;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'author': author,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory DiaryComment.fromJson(Map<String, dynamic> json) {
    return DiaryComment(
      author: json['author'] as String? ?? '评论人',
      content: json['content'] as String? ?? '',
      createdAt: _parseDateTime(json['created_at']),
    );
  }
}

class DiaryAttachment {
  const DiaryAttachment({
    required this.id,
    required this.path,
    required this.originalName,
    required this.createdAt,
  });

  final String id;
  final String path;
  final String originalName;
  final DateTime createdAt;

  List<String> get storedPaths {
    return [if (path.isNotEmpty) path];
  }

  DiaryAttachment copyWith({
    String? id,
    String? path,
    String? originalName,
    DateTime? createdAt,
  }) {
    return DiaryAttachment(
      id: id ?? this.id,
      path: path ?? this.path,
      originalName: originalName ?? this.originalName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'original_name': originalName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory DiaryAttachment.fromJson(Map<String, dynamic> json) {
    final path =
        (json['path'] as String?) ??
        (json['original_path'] as String?) ??
        (json['preview_path'] as String?) ??
        (json['thumbnail_path'] as String?) ??
        '';

    return DiaryAttachment(
      id: json['id'] as String? ?? 'att_unknown',
      path: path,
      originalName: json['original_name'] as String? ?? 'attachment.jpg',
      createdAt: _parseDateTime(json['created_at']),
    );
  }
}

class CoupleProfile {
  const CoupleProfile({
    required this.maleName,
    required this.femaleName,
    this.currentUserRole = 'male',
    required this.togetherSince,
    required this.isOnboarded,
  });

  final String maleName;
  final String femaleName;
  final String currentUserRole;
  final DateTime togetherSince;
  final bool isOnboarded;

  static String normalizeCurrentUserRole(String? role) {
    return role == 'female' ? 'female' : 'male';
  }

  static String? currentUserRoleFromJson(Map<String, dynamic> json) {
    if (!json.containsKey('current_user_role')) {
      return null;
    }
    return normalizeCurrentUserRole(json['current_user_role'] as String?);
  }

  bool get isCurrentUserMale => currentUserRole != 'female';
  String get currentUserPronoun => isCurrentUserMale ? '他' : '她';
  String get partnerPronoun => isCurrentUserMale ? '她' : '他';
  String get currentUserName => isCurrentUserMale ? maleName : femaleName;
  String get partnerName => isCurrentUserMale ? femaleName : maleName;

  CoupleProfile copyWith({
    String? maleName,
    String? femaleName,
    String? currentUserRole,
    DateTime? togetherSince,
    bool? isOnboarded,
  }) {
    return CoupleProfile(
      maleName: maleName ?? this.maleName,
      femaleName: femaleName ?? this.femaleName,
      currentUserRole: currentUserRole ?? this.currentUserRole,
      togetherSince: togetherSince ?? this.togetherSince,
      isOnboarded: isOnboarded ?? this.isOnboarded,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'male_name': maleName,
      'female_name': femaleName,
      'together_since': togetherSince.toIso8601String(),
      'is_onboarded': isOnboarded,
    };
  }

  factory CoupleProfile.fromJson(
    Map<String, dynamic> json, {
    String? currentUserRole,
  }) {
    return CoupleProfile(
      maleName:
          json['male_name'] as String? ?? json['my_name'] as String? ?? '他',
      femaleName:
          json['female_name'] as String? ??
          json['partner_name'] as String? ??
          '她',
      currentUserRole: normalizeCurrentUserRole(
        currentUserRole ?? json['current_user_role'] as String?,
      ),
      togetherSince: _parseDateTime(json['together_since']),
      isOnboarded: json['is_onboarded'] as bool? ?? false,
    );
  }
}

enum ScheduleItemType {
  oneTime,
  yearly;

  String get storageValue {
    return switch (this) {
      ScheduleItemType.oneTime => 'one_time',
      ScheduleItemType.yearly => 'yearly',
    };
  }

  static ScheduleItemType fromStorageValue(String? value) {
    return switch (value) {
      'yearly' => ScheduleItemType.yearly,
      _ => ScheduleItemType.oneTime,
    };
  }
}

class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.title,
    this.description,
    required this.date,
    required this.type,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? description;
  final DateTime date;
  final ScheduleItemType type;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isYearly => type == ScheduleItemType.yearly;

  DateTime nextOccurrenceOnOrAfter(DateTime from) {
    final anchor = DateTime(from.year, from.month, from.day);
    final baseDate = DateTime(date.year, date.month, date.day);
    if (type == ScheduleItemType.oneTime) {
      return baseDate;
    }

    var occurrence = _safeDate(anchor.year, date.month, date.day);
    if (occurrence.isBefore(anchor)) {
      occurrence = _safeDate(anchor.year + 1, date.month, date.day);
    }
    return occurrence;
  }

  DateTime occurrenceInYear(int year) {
    if (type == ScheduleItemType.oneTime) {
      return DateTime(date.year, date.month, date.day);
    }
    return _safeDate(year, date.month, date.day);
  }

  ScheduleItem copyWith({
    String? id,
    String? title,
    String? description,
    bool clearDescription = false,
    DateTime? date,
    ScheduleItemType? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return ScheduleItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: clearDescription ? null : description ?? this.description,
      date: date ?? this.date,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'type': type.storageValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      id: json['id'] as String? ?? 'schedule_unknown',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      date: _parseDateTime(json['date']),
      type: ScheduleItemType.fromStorageValue(json['type'] as String?),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: json['updated_at'] == null
          ? null
          : _parseDateTime(json['updated_at']),
    );
  }

  static String normalizeTitle(String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) {
      throw const FormatException('日程标题不能为空');
    }
    if (title.runes.length > 8) {
      throw const FormatException('日程标题不能超过 8 个字');
    }
    return title;
  }

  static int compareByDate(ScheduleItem a, ScheduleItem b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.title.compareTo(b.title);
  }

  static DateTime _safeDate(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > lastDay ? lastDay : day);
  }
}

class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.author,
    required this.title,
    required this.content,
    required this.mood,
    required this.createdAt,
    this.updatedAt,
    required this.comments,
    required this.attachments,
  });

  final String id;
  final String author;
  final String title;
  final String content;
  final String mood;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<DiaryComment> comments;
  final List<DiaryAttachment> attachments;

  int get commentCount => comments.length;
  bool get hasUpdates => updatedAt != null;

  String get summary {
    if (content.length <= 46) {
      return content;
    }
    return '${content.substring(0, 46)}...';
  }

  DiaryEntry copyWith({
    String? id,
    String? author,
    String? title,
    String? content,
    String? mood,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<DiaryComment>? comments,
    List<DiaryAttachment>? attachments,
    bool clearUpdatedAt = false,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      author: author ?? this.author,
      title: title ?? this.title,
      content: content ?? this.content,
      mood: mood ?? this.mood,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
      comments: comments ?? this.comments,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'schema_version': 2,
      'author': author,
      'title': title,
      'content': content,
      'mood': mood,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'comments': comments.map((comment) => comment.toJson()).toList(),
      'attachments': attachments
          .map((attachment) => attachment.toJson())
          .toList(),
    };
  }

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    final rawComments = json['comments'] as List<dynamic>? ?? <dynamic>[];
    final rawAttachments = json['attachments'] as List<dynamic>? ?? <dynamic>[];

    return DiaryEntry(
      id: json['id'] as String? ?? 'entry_${DateTime.now().microsecondsSinceEpoch}',
      author: json['author'] as String? ?? '他',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      mood: json['mood'] as String? ?? '开心',
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: json['updated_at'] == null
          ? null
          : _parseDateTime(json['updated_at']),
      comments: rawComments
          .map(
            (comment) => comment is Map<String, dynamic>
                ? DiaryComment.fromJson(comment)
                : null,
          )
          .whereType<DiaryComment>()
          .toList(),
      attachments: rawAttachments
          .map(
            (attachment) => attachment is Map<String, dynamic>
                ? DiaryAttachment.fromJson(attachment)
                : null,
          )
          .whereType<DiaryAttachment>()
          .toList(),
    );
  }
}

class DeletedDiaryEntry {
  const DeletedDiaryEntry({required this.entry, required this.deletedAt});

  final DiaryEntry entry;
  final DateTime deletedAt;

  Map<String, dynamic> toJson() {
    return {'entry': entry.toJson(), 'deleted_at': deletedAt.toIso8601String()};
  }

  factory DeletedDiaryEntry.fromJson(Map<String, dynamic> json) {
    return DeletedDiaryEntry(
      entry: DiaryEntry.fromJson(json['entry'] as Map<String, dynamic>),
      deletedAt: _parseDateTime(json['deleted_at']),
    );
  }
}

class DiaryDraft {
  const DiaryDraft({
    required this.title,
    required this.content,
    required this.mood,
    required this.selectedDate,
    required this.attachments,
    required this.savedAt,
  });

  final String title;
  final String content;
  final String mood;
  final DateTime selectedDate;
  final List<DiaryAttachment> attachments;
  final DateTime savedAt;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'mood': mood,
      'selected_date': selectedDate.toIso8601String(),
      'attachments': attachments
          .map((attachment) => attachment.toJson())
          .toList(),
      'saved_at': savedAt.toIso8601String(),
    };
  }

  factory DiaryDraft.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'] as List<dynamic>? ?? <dynamic>[];

    return DiaryDraft(
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      mood: json['mood'] as String? ?? '开心',
      selectedDate: _parseDateTime(json['selected_date']),
      attachments: rawAttachments
          .map(
            (attachment) =>
                DiaryAttachment.fromJson(attachment as Map<String, dynamic>),
          )
          .toList(),
      savedAt: _parseDateTime(json['saved_at']),
    );
  }
}

const List<String> kDiaryMoods = [
  '开心',
  '安心',
  '温柔',
  '想念',
  '真诚',
  '治愈',
  '甜',
  '难过',
  '委屈',
  '生气',
  '焦虑',
  '孤独',
  '失落',
];

DateTime _parseDateTime(dynamic value) {
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (error) {
      AppLog.error('日期解析失败: $error, 原始值: $value');
      return DateTime.now();
    }
  }
  return DateTime.now();
}
