part of '../../app.dart';

class EntryDetailPage extends StatefulWidget {
  const EntryDetailPage({
    super.key,
    required this.profile,
    required this.entry,
    required this.rootDirectoryPath,
    required this.writeLockedListenable,
    required this.onWriteBlocked,
    required this.onAddComment,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final CoupleProfile profile;
  final DiaryEntry entry;
  final String? rootDirectoryPath;
  final ValueListenable<bool> writeLockedListenable;
  final VoidCallback onWriteBlocked;
  final Future<DiaryEntry> Function(String entryId, DiaryComment comment)
  onAddComment;
  final Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry;
  final Future<void> Function(DiaryEntry entry) onDeleteEntry;

  @override
  State<EntryDetailPage> createState() => _EntryDetailPageState();
}

class _EntryDetailPageState extends State<EntryDetailPage> {
  final TextEditingController _commentController = TextEditingController();

  late DiaryEntry _entry;
  bool _isSavingComment = false;

  @override
  void initState() {
    super.initState();
    widget.writeLockedListenable.addListener(_handleWriteLockChanged);
    _entry = widget.entry;
  }

  @override
  void dispose() {
    widget.writeLockedListenable.removeListener(_handleWriteLockChanged);
    _commentController.dispose();
    super.dispose();
  }

  bool get _isWriteLocked => widget.writeLockedListenable.value;

  void _handleWriteLockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _guardWritableAction() {
    if (!_isWriteLocked) {
      return true;
    }
    widget.onWriteBlocked();
    return false;
  }

  Future<void> _submitComment() async {
    if (!_guardWritableAction()) {
      return;
    }

    final content = _commentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先写点内容再发表评论')));
      return;
    }

    setState(() {
      _isSavingComment = true;
    });

    try {
      final updatedEntry = await widget.onAddComment(
        _entry.id,
        DiaryComment(
          author: widget.profile.currentUserPronoun,
          content: content,
          createdAt: DateTime.now(),
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _entry = updatedEntry;
        _commentController.clear();
        _isSavingComment = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingComment = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评论保存失败，请稍后再试')));
    }
  }

  Future<void> _editEntry() async {
    if (!_guardWritableAction()) {
      return;
    }

    final updatedEntry = await widget.onEditEntry(_entry);
    if (updatedEntry == null || !mounted) {
      return;
    }

    setState(() {
      _entry = updatedEntry;
    });
  }

  Future<void> _deleteEntry() async {
    if (!_guardWritableAction()) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这篇日记？'),
          content: Text('《${_entry.title}》会从本地移除，并记录删除状态以便后续同步。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await widget.onDeleteEntry(_entry);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isWriteLocked = _isWriteLocked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日记详情'),
        actions: [
          IconButton(
            onPressed: isWriteLocked ? widget.onWriteBlocked : _editEntry,
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑日记',
          ),
          IconButton(
            onPressed: isWriteLocked ? widget.onWriteBlocked : _deleteEntry,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除日记',
          ),
        ],
      ),
      body: DiaryPage(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DiaryHero(
              eyebrow: '日记详情',
              title: _entry.title,
              subtitle: _entry.content,
              footer: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DiaryBadge(label: _entry.author, tone: DiaryBadgeTone.sand),
                  DiaryBadge(label: _entry.mood),
                  DiaryBadge(
                    label: formatDiaryDate(_entry.createdAt),
                    tone: DiaryBadgeTone.ink,
                  ),
                  DiaryBadge(
                    label: '${_entry.attachments.length} 张图',
                    tone: DiaryBadgeTone.sand,
                  ),
                  if (_entry.updatedAt != null)
                    DiaryBadge(
                      label: '最近更新 ${formatDiaryShortDate(_entry.updatedAt!)}',
                      tone: DiaryBadgeTone.ink,
                    ),
                ],
              ),
            ),
            if (_entry.attachments.isNotEmpty) ...[
              const SizedBox(height: 22),
              const DiarySectionHeader(title: '附图'),
              const SizedBox(height: 12),
              DiaryPanel(
                child: AttachmentGrid(
                  attachments: _entry.attachments,
                  rootDirectoryPath: widget.rootDirectoryPath,
                ),
              ),
            ],
            const SizedBox(height: 22),
            const DiarySectionHeader(title: '评论区'),
            const SizedBox(height: 12),
            DiaryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '将以 ${widget.profile.currentUserPronoun} 的身份发表评论。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: DiaryPalette.wine),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _commentController,
                    enabled: !isWriteLocked,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '写一条评论',
                      hintText: '比如：这个瞬间我也想一直记得。',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSavingComment
                          ? null
                          : isWriteLocked
                          ? widget.onWriteBlocked
                          : _submitComment,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text(
                        _isSavingComment
                            ? '保存中...'
                            : isWriteLocked
                            ? '同步中，稍后评论'
                            : '发表评论',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_entry.comments.isEmpty)
              const DiaryEmptyState(
                title: '还没有评论',
                icon: Icons.chat_bubble_outline_rounded,
              )
            else
              ..._entry.comments.map(
                (comment) => CommentCard(comment: comment),
              ),
          ],
        ),
      ),
    );
  }
}

class CreateEntryPage extends StatefulWidget {
  const CreateEntryPage({
    super.key,
    required this.storage,
    required this.profile,
    required this.writeLockedListenable,
    required this.onWriteBlocked,
    this.initialEntry,
    this.rootDirectoryPath,
  });

  final DiaryStorage storage;
  final CoupleProfile profile;
  final ValueListenable<bool> writeLockedListenable;
  final VoidCallback onWriteBlocked;
  final DiaryEntry? initialEntry;
  final String? rootDirectoryPath;

  @override
  State<CreateEntryPage> createState() => _CreateEntryPageState();
}

class _CreateEntryPageState extends State<CreateEntryPage>
    with WidgetsBindingObserver {
  static const _draftAutosaveDelay = Duration(seconds: 2);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final ImagePicker _imagePicker = ImagePicker();

  late DateTime _selectedDate;
  late String _selectedMood;
  bool _isPickingImages = false;
  bool _isPreparingDraft = true;
  bool _isSavingDraftSilently = false;
  Timer? _draftAutosaveTimer;
  List<DiaryAttachment> _attachments = [];
  DiaryDraft? _lastSavedDraft;
  late String _entryAuthor;

  bool get _isEditMode => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.writeLockedListenable.addListener(_handleWriteLockChanged);
    _titleController = TextEditingController(
      text: widget.initialEntry?.title ?? '',
    );
    _contentController = TextEditingController(
      text: widget.initialEntry?.content ?? '',
    );
    _selectedDate = widget.initialEntry?.createdAt ?? DateTime.now();
    _selectedMood = widget.initialEntry?.mood ?? kDiaryMoods.first;
    _entryAuthor =
        widget.initialEntry?.author ?? widget.profile.currentUserPronoun;
    _attachments = List<DiaryAttachment>.from(
      widget.initialEntry?.attachments ?? const [],
    );
    _titleController.addListener(_scheduleDraftAutosave);
    _contentController.addListener(_scheduleDraftAutosave);
    if (_isEditMode) {
      _isPreparingDraft = false;
    } else {
      _restoreDraft();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftAutosaveTimer?.cancel();
    unawaited(_saveDraftSilently(force: true));
    widget.writeLockedListenable.removeListener(_handleWriteLockChanged);
    _titleController.removeListener(_scheduleDraftAutosave);
    _contentController.removeListener(_scheduleDraftAutosave);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_saveDraftSilently(force: true));
    }
  }

  bool get _isWriteLocked => widget.writeLockedListenable.value;

  void _handleWriteLockChanged() {
    if (mounted) {
      setState(() {});
    }
    if (!_isWriteLocked) {
      _scheduleDraftAutosave();
    }
  }

  bool _guardWritableAction() {
    if (!_isWriteLocked) {
      return true;
    }
    widget.onWriteBlocked();
    return false;
  }

  Future<void> _restoreDraft() async {
    final draft = await widget.storage.loadEntryDraft();
    if (!mounted) {
      return;
    }

    if (draft != null) {
      _titleController.text = draft.title;
      _contentController.text = draft.content;
      _selectedDate = draft.selectedDate;
      _selectedMood = draft.mood;
      _attachments = List<DiaryAttachment>.from(draft.attachments);
      _lastSavedDraft = draft;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复上次未完成的草稿')));
      });
    }

    setState(() {
      _isPreparingDraft = false;
    });
    _scheduleDraftAutosave();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择日记日期',
      cancelText: '取消',
      confirmText: '确定',
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _selectedDate.hour,
        _selectedDate.minute,
      );
    });
    _scheduleDraftAutosave();
  }

  Future<void> _pickImages() async {
    if (!_guardWritableAction()) {
      return;
    }

    if (kIsWeb) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('网页端图片保存这版先只支持安卓真机/模拟器')));
      return;
    }

    final importMode = await _showAttachmentImportModeSheet();
    if (!mounted || importMode == null) {
      return;
    }

    setState(() {
      _isPickingImages = true;
    });

    try {
      final files = await _imagePicker.pickMultiImage(
        imageQuality: importMode == _AttachmentImportMode.compressed
            ? 85
            : null,
        limit: 6,
      );

      if (files.isEmpty) {
        if (mounted) {
          setState(() {
            _isPickingImages = false;
          });
        }
        return;
      }

      final List<DiaryAttachment> savedAttachments = [];
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final savedAttachment = await widget.storage.importAttachment(
          sourcePath: file.path,
          fileName: '${index}_${file.name}',
          keepOriginal: importMode == _AttachmentImportMode.original,
        );
        savedAttachments.add(savedAttachment);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _attachments = [..._attachments, ...savedAttachments];
        _isPickingImages = false;
      });
      _scheduleDraftAutosave();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPickingImages = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片导入失败，请检查权限或稍后再试')));
    }
  }

  Future<void> _removeAttachment(DiaryAttachment attachment) async {
    if (!_guardWritableAction()) {
      return;
    }

    if (_isTemporaryAttachment(attachment)) {
      await widget.storage.deleteAttachments([attachment]);
    }

    setState(() {
      _attachments = _attachments
          .where((item) => item.id != attachment.id)
          .toList();
    });
    _scheduleDraftAutosave();
  }

  Future<_AttachmentImportMode?> _showAttachmentImportModeSheet() {
    return showModalBottomSheet<_AttachmentImportMode>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导入图片',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.data_saver_on_rounded),
                  title: const Text('节省流量'),
                  onTap: () {
                    Navigator.of(context).pop(_AttachmentImportMode.compressed);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.high_quality_rounded),
                  title: const Text('原图导入'),
                  onTap: () {
                    Navigator.of(context).pop(_AttachmentImportMode.original);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scheduleDraftAutosave() {
    if (_isEditMode || _isPreparingDraft || _isWriteLocked) {
      return;
    }
    _draftAutosaveTimer?.cancel();
    _draftAutosaveTimer = Timer(_draftAutosaveDelay, () {
      unawaited(_saveDraftSilently());
    });
  }

  Future<void> _saveDraftSilently({bool force = false}) async {
    if (_isEditMode ||
        _isPreparingDraft ||
        _isWriteLocked ||
        _isSavingDraftSilently) {
      return;
    }

    _draftAutosaveTimer?.cancel();
    final draft = _currentDraft();
    final baseline = _lastSavedDraft;
    final isEmpty = _isDraftEmpty(draft);
    final isChanged =
        baseline == null ||
        draft.title != baseline.title ||
        draft.content != baseline.content ||
        draft.mood != baseline.mood ||
        !isSameDay(draft.selectedDate, baseline.selectedDate) ||
        !_sameAttachments(draft.attachments, baseline.attachments);

    if (!force && (!isChanged || isEmpty)) {
      return;
    }
    if (isEmpty) {
      if (baseline != null) {
        await widget.storage.clearEntryDraft();
        _lastSavedDraft = null;
      }
      return;
    }

    _isSavingDraftSilently = true;
    try {
      await widget.storage.saveEntryDraft(draft);
      _lastSavedDraft = draft;
    } finally {
      _isSavingDraftSilently = false;
    }
  }

  Future<void> _saveDraft() async {
    if (!_guardWritableAction()) {
      return;
    }

    _draftAutosaveTimer?.cancel();
    final draft = _currentDraft();
    if (_isDraftEmpty(draft)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先写一点内容再保存草稿')));
      return;
    }

    await widget.storage.saveEntryDraft(draft);
    _lastSavedDraft = draft;
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('草稿已保存')));
  }

  bool get _isDirty {
    if (_isEditMode) {
      final initialEntry = widget.initialEntry!;
      return _titleController.text.trim() != initialEntry.title ||
          _contentController.text.trim() != initialEntry.content ||
          _selectedMood != initialEntry.mood ||
          !isSameDay(_selectedDate, initialEntry.createdAt) ||
          !_sameAttachments(_attachments, initialEntry.attachments);
    }

    final currentDraft = _currentDraft();
    final baseline = _lastSavedDraft;
    if (baseline == null) {
      return !_isDraftEmpty(currentDraft);
    }

    return currentDraft.title != baseline.title ||
        currentDraft.content != baseline.content ||
        currentDraft.mood != baseline.mood ||
        !isSameDay(currentDraft.selectedDate, baseline.selectedDate) ||
        !_sameAttachments(currentDraft.attachments, baseline.attachments);
  }

  Future<bool> _confirmExit() async {
    if (!_isDirty) {
      return true;
    }

    final action = await showDialog<_EditorExitAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_isEditMode ? '放弃本次修改？' : '离开前要怎么处理？'),
          content: Text(_isEditMode ? '你刚刚修改的内容还没有保存。' : '这篇日记还没有保存，可以先存成草稿。'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_EditorExitAction.cancel),
              child: const Text('继续编辑'),
            ),
            if (!_isEditMode)
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_EditorExitAction.saveDraft),
                child: const Text('存为草稿'),
              ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_EditorExitAction.discard),
              child: const Text('放弃'),
            ),
          ],
        );
      },
    );

    switch (action) {
      case _EditorExitAction.saveDraft:
        if (_isWriteLocked) {
          widget.onWriteBlocked();
          return false;
        }
        await _saveDraft();
        return true;
      case _EditorExitAction.discard:
        if (_attachments.any(_isTemporaryAttachment) && _isWriteLocked) {
          widget.onWriteBlocked();
          return false;
        }
        await _discardTemporaryAttachments();
        return true;
      case _EditorExitAction.cancel:
      case null:
        return false;
    }
  }

  Future<void> _handleBack() async {
    final shouldPop = await _confirmExit();
    if (!mounted || !shouldPop) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (!_guardWritableAction()) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final originalCreatedAt = widget.initialEntry?.createdAt ?? now;

    final entry = DiaryEntry(
      id: widget.initialEntry?.id ?? 'entry_${now.microsecondsSinceEpoch}',
      author: _entryAuthor,
      title: title.isEmpty ? _guessTitle(content) : title,
      content: content,
      mood: _selectedMood,
      createdAt: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        originalCreatedAt.hour,
        originalCreatedAt.minute,
      ),
      updatedAt: _isEditMode ? now : null,
      comments: widget.initialEntry?.comments ?? const [],
      attachments: _attachments,
    );

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(entry);
  }

  DiaryDraft _currentDraft() {
    return DiaryDraft(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      mood: _selectedMood,
      selectedDate: _selectedDate,
      attachments: List<DiaryAttachment>.from(_attachments),
      savedAt: DateTime.now(),
    );
  }

  bool _isDraftEmpty(DiaryDraft draft) {
    return draft.title.isEmpty &&
        draft.content.isEmpty &&
        draft.attachments.isEmpty &&
        draft.mood == kDiaryMoods.first &&
        isSameDay(draft.selectedDate, DateTime.now());
  }

  Future<void> _discardTemporaryAttachments() async {
    final temporaryAttachments = _attachments
        .where(_isTemporaryAttachment)
        .toList();
    await widget.storage.deleteAttachments(temporaryAttachments);
    if (!_isEditMode) {
      await widget.storage.clearEntryDraft();
    }
  }

  bool _sameAttachments(
    List<DiaryAttachment> left,
    List<DiaryAttachment> right,
  ) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      final current = left[index];
      final baseline = right[index];
      if (current.id != baseline.id ||
          current.path != baseline.path ||
          current.thumbnailPath != baseline.thumbnailPath ||
          current.previewPath != baseline.previewPath ||
          current.originalPath != baseline.originalPath) {
        return false;
      }
    }
    return true;
  }

  bool _isTemporaryAttachment(DiaryAttachment attachment) {
    return attachment.storedPaths.any((path) => path.startsWith('drafts/'));
  }

  String _guessTitle(String content) {
    if (content.length <= 10) {
      return content;
    }
    return '${content.substring(0, 10)}...';
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreparingDraft) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isWriteLocked = _isWriteLocked;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(_isEditMode ? '编辑日记' : '新建日记'),
          actions: [
            if (!_isEditMode)
              TextButton(
                onPressed: isWriteLocked ? widget.onWriteBlocked : _saveDraft,
                child: Text(isWriteLocked ? '同步中' : '存草稿'),
              ),
            TextButton(
              onPressed: isWriteLocked ? widget.onWriteBlocked : _submit,
              child: Text(isWriteLocked ? '稍后保存' : '保存'),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: DiaryPage(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DiaryCompactHeader(
                  eyebrow: _isEditMode ? '编辑日记' : '新建日记',
                  title: _isEditMode ? '编辑这篇日记' : '写一篇新日记',
                ),
                const SizedBox(height: 20),
                DiaryPanel(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [DiaryBadge(label: _entryAuthor)],
                  ),
                ),
                const SizedBox(height: 20),
                DiaryPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '标题（可选）',
                          hintText: '比如：今天一起散步',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _contentController,
                        minLines: 6,
                        maxLines: 10,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          labelText: '内容',
                          hintText: '写下今天发生的小事、心情，或者想对对方说的话。',
                          alignLabelWithHint: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '内容不能为空';
                          }
                          if (value.trim().length < 5) {
                            return '再多写一点，至少 5 个字';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const DiarySectionHeader(title: '状态'),
                const SizedBox(height: 12),
                DiaryPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isPickingImages
                              ? null
                              : isWriteLocked
                              ? widget.onWriteBlocked
                              : _pickImages,
                          icon: const Icon(Icons.add_photo_alternate_rounded),
                          label: Text(
                            isWriteLocked
                                ? '同步中，稍后添加照片'
                                : _isPickingImages
                                ? '正在处理照片...'
                                : _attachments.isEmpty
                                ? '添加照片'
                                : '继续添加照片（已添加 ${_attachments.length} 张）',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: kDiaryMoods.map((mood) {
                          return ChoiceChip(
                            label: Text(mood),
                            selected: _selectedMood == mood,
                            onSelected: (_) {
                              setState(() {
                                _selectedMood = mood;
                              });
                              _scheduleDraftAutosave();
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text('日记日期：${formatDiaryDate(_selectedDate)}'),
                      ),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        EditableAttachmentGrid(
                          attachments: _attachments,
                          rootDirectoryPath: widget.rootDirectoryPath,
                          onRemove: (attachment) {
                            if (isWriteLocked) {
                              widget.onWriteBlocked();
                              return;
                            }
                            _removeAttachment(attachment);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const DraftHintCard(),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isWriteLocked ? widget.onWriteBlocked : _submit,
                  icon: const Icon(Icons.favorite_rounded),
                  label: Text(
                    isWriteLocked
                        ? '同步中，稍后保存'
                        : _isEditMode
                        ? '保存修改'
                        : '保存这篇日记',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DraftHintCard extends StatelessWidget {
  const DraftHintCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DiaryPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: DiaryPalette.mist,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              color: DiaryPalette.rose,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '支持日记、附图、评论和本地保存。',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: DiaryPalette.wine,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _EditorExitAction { cancel, saveDraft, discard }

enum _AttachmentImportMode { compressed, original }

class CommentCard extends StatelessWidget {
  const CommentCard({super.key, required this.comment});

  final DiaryComment comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DiaryPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: DiaryPalette.mist,
                  child: Text(
                    comment.author.characters.first,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: DiaryPalette.rose,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    comment.author,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: DiaryPalette.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${formatDiaryShortDate(comment.createdAt)} ${formatDiaryTime(comment.createdAt)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: DiaryPalette.wine),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              comment.content,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: DiaryPalette.wine,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String resolveStoredPath(String? rootDirectoryPath, String storedPath) {
  final normalized = storedPath.replaceAll('\\', '/');
  final isAbsoluteUnix = normalized.startsWith('/');
  final isAbsoluteWindows = RegExp(r'^[a-zA-Z]:/').hasMatch(normalized);
  if (isAbsoluteUnix || isAbsoluteWindows || rootDirectoryPath == null) {
    return storedPath;
  }

  final normalizedRoot = rootDirectoryPath.replaceAll('\\', '/');
  return '$normalizedRoot/$normalized';
}
