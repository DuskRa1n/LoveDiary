part of '../../app.dart';

class DustbinPage extends StatefulWidget {
  const DustbinPage({
    super.key,
    required this.storage,
    required this.writeLockedListenable,
    required this.onWriteBlocked,
  });

  final DiaryStorage storage;
  final ValueListenable<bool> writeLockedListenable;
  final VoidCallback onWriteBlocked;

  @override
  State<DustbinPage> createState() => _DustbinPageState();
}

class _DustbinPageState extends State<DustbinPage> {
  List<DeletedDiaryEntry> _deletedEntries = const [];
  bool _isLoading = true;
  String? _processingEntryId;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    widget.writeLockedListenable.addListener(_handleWriteLockChanged);
    _loadDeletedEntries();
  }

  @override
  void dispose() {
    widget.writeLockedListenable.removeListener(_handleWriteLockChanged);
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

  Future<void> _loadDeletedEntries() async {
    final deletedEntries = await widget.storage.loadDustbinEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _deletedEntries = deletedEntries;
      _isLoading = false;
    });
  }

  Future<void> _restoreEntry(DeletedDiaryEntry deletedEntry) async {
    if (!_guardWritableAction()) {
      return;
    }

    setState(() {
      _processingEntryId = deletedEntry.entry.id;
    });

    await widget.storage.restoreDeletedEntry(deletedEntry);
    _hasChanged = true;
    await _loadDeletedEntries();

    if (!mounted) {
      return;
    }
    setState(() {
      _processingEntryId = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已恢复 ${deletedEntry.entry.title}')));
  }

  Future<void> _deleteForever(DeletedDiaryEntry deletedEntry) async {
    if (!_guardWritableAction()) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('彻底删除这篇日记？'),
          content: const Text('这次删除不会进入新的回收站，也不能再恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('彻底删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _processingEntryId = deletedEntry.entry.id;
    });

    await widget.storage.permanentlyDeleteDeletedEntry(deletedEntry);
    _hasChanged = true;
    await _loadDeletedEntries();

    if (!mounted) {
      return;
    }
    setState(() {
      _processingEntryId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已彻底删除 ${deletedEntry.entry.title}')),
    );
  }

  int _remainingDays(DeletedDiaryEntry deletedEntry) {
    final expiresAt = deletedEntry.deletedAt.add(const Duration(days: 7));
    final difference = expiresAt.difference(DateTime.now());
    if (difference.isNegative) {
      return 0;
    }
    return difference.inDays + 1;
  }

  void _closePage() {
    Navigator.of(context).pop(_hasChanged);
  }

  @override
  Widget build(BuildContext context) {
    final isWriteLocked = _isWriteLocked;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('回收站'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : DiaryPage(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: _deletedEntries.isEmpty
                  ? const DiaryEmptyState(
                      title: '回收站是空的',
                      icon: Icons.restore_from_trash_rounded,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DiaryCompactHeader(
                          eyebrow: '删除保护',
                          title: '最近删除的日记',
                        ),
                        const SizedBox(height: 20),
                        ..._deletedEntries.map((deletedEntry) {
                          final entry = deletedEntry.entry;
                          final isProcessing = _processingEntryId == entry.id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: DiaryPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                color: DiaryPalette.ink,
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      ),
                                      if (isProcessing)
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.summary,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: DiaryPalette.wine,
                                          height: 1.5,
                                        ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      DiaryBadge(label: entry.mood),
                                      DiaryBadge(
                                        label:
                                            '删除于 ${formatDiaryDate(deletedEntry.deletedAt)}',
                                        tone: DiaryBadgeTone.ink,
                                      ),
                                      DiaryBadge(
                                        label: '${entry.attachments.length} 张图',
                                        tone: DiaryBadgeTone.sand,
                                      ),
                                      DiaryBadge(
                                        label: '${entry.commentCount} 条评论',
                                        tone: DiaryBadgeTone.ink,
                                      ),
                                      DiaryBadge(
                                        label:
                                            '剩余 ${_remainingDays(deletedEntry)} 天',
                                        tone: DiaryBadgeTone.sand,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: isProcessing
                                            ? null
                                            : isWriteLocked
                                            ? widget.onWriteBlocked
                                            : () => _restoreEntry(deletedEntry),
                                        icon: const Icon(Icons.undo_rounded),
                                        label: const Text('恢复'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: isProcessing
                                            ? null
                                            : isWriteLocked
                                            ? widget.onWriteBlocked
                                            : () =>
                                                  _deleteForever(deletedEntry),
                                        icon: const Icon(
                                          Icons.delete_forever_rounded,
                                        ),
                                        label: const Text('彻底删除'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
            ),
    );
  }
}
