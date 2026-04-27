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
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class DiaryAttachment {
  const DiaryAttachment({
    required this.id,
    required this.path,
    required this.originalName,
    required this.createdAt,
    this.thumbnailPath,
    this.previewPath,
    this.originalPath,
    this.hasLocalOriginal = false,
    this.syncOriginal = false,
  });

  final String id;
  final String path;
  final String originalName;
  final DateTime createdAt;
  final String? thumbnailPath;
  final String? previewPath;
  final String? originalPath;
  final bool hasLocalOriginal;
  final bool syncOriginal;

  String get thumbnailOrFallbackPath =>
      thumbnailPath ?? previewPath ?? pathOrOriginalFallback ?? '';

  String get previewOrFallbackPath =>
      previewPath ?? pathOrOriginalFallback ?? thumbnailPath ?? '';

  String get originalOrFallbackPath =>
      originalPath ??
      pathOrOriginalFallback ??
      previewPath ??
      thumbnailPath ??
      '';

  String? get pathOrOriginalFallback {
    if (path.isNotEmpty) {
      return path;
    }
    return originalPath;
  }

  List<String> get storedPaths {
    return <String?>[
      path.isEmpty ? null : path,
      thumbnailPath,
      previewPath,
      originalPath,
    ].whereType<String>().where((item) => item.isNotEmpty).toSet().toList();
  }

  DiaryAttachment copyWith({
    String? id,
    String? path,
    String? originalName,
    DateTime? createdAt,
    String? thumbnailPath,
    String? previewPath,
    String? originalPath,
    bool? hasLocalOriginal,
    bool? syncOriginal,
  }) {
    return DiaryAttachment(
      id: id ?? this.id,
      path: path ?? this.path,
      originalName: originalName ?? this.originalName,
      createdAt: createdAt ?? this.createdAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      previewPath: previewPath ?? this.previewPath,
      originalPath: originalPath ?? this.originalPath,
      hasLocalOriginal: hasLocalOriginal ?? this.hasLocalOriginal,
      syncOriginal: syncOriginal ?? this.syncOriginal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'thumbnail_path': thumbnailPath,
      'preview_path': previewPath,
      'original_path': originalPath,
      'original_name': originalName,
      'created_at': createdAt.toIso8601String(),
      'has_local_original': hasLocalOriginal,
      'sync_original': syncOriginal,
    };
  }

  factory DiaryAttachment.fromJson(Map<String, dynamic> json) {
    return DiaryAttachment(
      id: json['id'] as String? ?? 'att_unknown',
      path: json['path'] as String? ?? '',
      thumbnailPath: json['thumbnail_path'] as String?,
      previewPath: json['preview_path'] as String?,
      originalPath: json['original_path'] as String?,
      originalName: json['original_name'] as String? ?? 'attachment.jpg',
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      hasLocalOriginal: json['has_local_original'] as bool? ?? false,
      syncOriginal: json['sync_original'] as bool? ?? false,
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
      'current_user_role': currentUserRole,
      'together_since': togetherSince.toIso8601String(),
      'is_onboarded': isOnboarded,
    };
  }

  factory CoupleProfile.fromJson(Map<String, dynamic> json) {
    return CoupleProfile(
      maleName:
          json['male_name'] as String? ?? json['my_name'] as String? ?? '他',
      femaleName:
          json['female_name'] as String? ??
          json['partner_name'] as String? ??
          '她',
      currentUserRole: (json['current_user_role'] as String?) == 'female'
          ? 'female'
          : 'male',
      togetherSince: DateTime.parse(
        json['together_since'] as String? ?? DateTime.now().toIso8601String(),
      ),
      isOnboarded: json['is_onboarded'] as bool? ?? false,
    );
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
      id: json['id'] as String,
      author: json['author'] as String? ?? '他',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      mood: json['mood'] as String? ?? '开心',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      comments: rawComments
          .map(
            (comment) => DiaryComment.fromJson(comment as Map<String, dynamic>),
          )
          .toList(),
      attachments: rawAttachments
          .map(
            (attachment) =>
                DiaryAttachment.fromJson(attachment as Map<String, dynamic>),
          )
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
      deletedAt: DateTime.parse(json['deleted_at'] as String),
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
      selectedDate: DateTime.parse(
        json['selected_date'] as String? ?? DateTime.now().toIso8601String(),
      ),
      attachments: rawAttachments
          .map(
            (attachment) =>
                DiaryAttachment.fromJson(attachment as Map<String, dynamic>),
          )
          .toList(),
      savedAt: DateTime.parse(
        json['saved_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}
