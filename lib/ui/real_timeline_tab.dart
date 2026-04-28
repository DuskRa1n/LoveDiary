import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import 'diary_design.dart';

class RealTimelineTab extends StatefulWidget {
  const RealTimelineTab({
    super.key,
    required this.entries,
    required this.rootDirectoryPath,
    required this.isWriteLocked,
    required this.onWriteBlocked,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
    this.topContentInset = 0,
  });

  final List<DiaryEntry> entries;
  final String? rootDirectoryPath;
  final bool isWriteLocked;
  final VoidCallback onWriteBlocked;
  final ValueChanged<DiaryEntry> onOpenEntry;
  final Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry;
  final Future<void> Function(DiaryEntry entry) onDeleteEntry;
  final double topContentInset;

  @override
  State<RealTimelineTab> createState() => _RealTimelineTabState();
}

class _RealTimelineTabState extends State<RealTimelineTab> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedMood;
  DateTime? _selectedDate;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedMood = null;
      _selectedDate = null;
    });
  }

  Future<void> _confirmDelete(DiaryEntry entry) async {
    if (widget.isWriteLocked) {
      widget.onWriteBlocked();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这篇日记？'),
          content: Text('《${entry.title}》会先进入回收站，7 天后才会彻底清理。'),
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

    await widget.onDeleteEntry(entry);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final moods = widget.entries.map((entry) => entry.mood).toSet().toList()
      ..sort();
    final filteredEntries = widget.entries.where((entry) {
      final matchesQuery =
          query.isEmpty ||
          entry.title.toLowerCase().contains(query) ||
          entry.content.toLowerCase().contains(query);
      final matchesMood = _selectedMood == null || entry.mood == _selectedMood;
      final matchesDate =
          _selectedDate == null ||
          isSameDiaryDay(entry.createdAt, _selectedDate!);
      return matchesQuery && matchesMood && matchesDate;
    }).toList();
    final hasFilter =
        query.isNotEmpty || _selectedMood != null || _selectedDate != null;

    final effectivePadding = const EdgeInsets.fromLTRB(18, 14, 18, 112)
        .copyWith(
          top: 14 + MediaQuery.paddingOf(context).top + widget.topContentInset,
        );
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiaryHero(
          eyebrow: '回忆',
          title: '时光轴',
          footer: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              DiaryBadge(label: '${widget.entries.length} 篇'),
              if (_selectedMood != null)
                DiaryBadge(label: _selectedMood!, tone: DiaryBadgeTone.sand),
              if (_selectedDate != null)
                DiaryBadge(
                  label: formatDiaryDate(_selectedDate!),
                  tone: DiaryBadgeTone.ink,
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _TimelineFilterPanel(
          controller: _searchController,
          moods: moods,
          selectedMood: _selectedMood,
          selectedDate: _selectedDate,
          hasFilter: hasFilter,
          onQueryChanged: () => setState(() {}),
          onMoodSelected: (mood) {
            setState(() {
              _selectedMood = mood;
            });
          },
          onPickDate: _pickDate,
          onClear: _clearFilters,
        ),
        const SizedBox(height: 24),
        DiarySectionHeader(title: hasFilter ? '筛选结果' : '日记目录'),
        const SizedBox(height: 14),
      ],
    );

    if (widget.entries.isEmpty || filteredEntries.isEmpty) {
      return ListView(
        padding: effectivePadding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          header,
          if (widget.entries.isEmpty)
            const DiaryEmptyState(title: '还没有日记')
          else
            const DiaryEmptyState(title: '没有匹配结果'),
        ],
      );
    }

    return ListView.builder(
      padding: effectivePadding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      cacheExtent: 900,
      itemCount: filteredEntries.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return header;
        }

        final entryIndex = index - 1;
        final entry = filteredEntries[entryIndex];
        return _TimelineEntryRow(
          entry: entry,
          rootDirectoryPath: widget.rootDirectoryPath,
          isFirst: entryIndex == 0,
          isLast: entryIndex == filteredEntries.length - 1,
          onTap: () => widget.onOpenEntry(entry),
          onEdit: () {
            if (widget.isWriteLocked) {
              widget.onWriteBlocked();
              return;
            }
            widget.onEditEntry(entry);
          },
          onDelete: () => _confirmDelete(entry),
        );
      },
    );
  }
}

class _TimelineFilterPanel extends StatelessWidget {
  const _TimelineFilterPanel({
    required this.controller,
    required this.moods,
    required this.selectedMood,
    required this.selectedDate,
    required this.hasFilter,
    required this.onQueryChanged,
    required this.onMoodSelected,
    required this.onPickDate,
    required this.onClear,
  });

  final TextEditingController controller;
  final List<String> moods;
  final String? selectedMood;
  final DateTime? selectedDate;
  final bool hasFilter;
  final VoidCallback onQueryChanged;
  final ValueChanged<String?> onMoodSelected;
  final VoidCallback onPickDate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DiaryPanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: '搜索日记...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          controller.clear();
                          onQueryChanged();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              onChanged: (_) => onQueryChanged(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            onPressed: () => _openFilterSheet(context),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('筛选'),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '筛选日记',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: DiaryPalette.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('全部心情'),
                      selected: selectedMood == null,
                      onSelected: (_) {
                        onMoodSelected(null);
                        Navigator.of(context).pop();
                      },
                    ),
                    ...moods.map(
                      (mood) => ChoiceChip(
                        label: Text(mood),
                        selected: selectedMood == mood,
                        onSelected: (_) {
                          onMoodSelected(mood);
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onPickDate();
                  },
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    selectedDate == null
                        ? '选择日期'
                        : formatDiaryDate(selectedDate!),
                  ),
                ),
                if (hasFilter) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      onClear();
                      Navigator.of(context).pop();
                    },
                    child: const Text('清空筛选'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimelineEntryRow extends StatelessWidget {
  const _TimelineEntryRow({
    required this.entry,
    required this.rootDirectoryPath,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final DiaryEntry entry;
  final String? rootDirectoryPath;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 64,
            child: _TimelineRail(
              date: entry.createdAt,
              isFirst: isFirst,
              isLast: isLast,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: _TimelineEntryCard(
                entry: entry,
                rootDirectoryPath: rootDirectoryPath,
                onTap: onTap,
                onEdit: onEdit,
                onDelete: onDelete,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({
    required this.date,
    required this.isFirst,
    required this.isLast,
  });

  final DateTime date;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          top: isFirst ? 30 : 0,
          bottom: isLast ? 30 : 0,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              color: DiaryPalette.rose.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            children: [
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: DiaryPalette.mist.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: DiaryPalette.white, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      '${date.day}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: DiaryPalette.rose,
                        fontWeight: FontWeight.w900,
                        height: 0.95,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${date.month}月',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: DiaryPalette.wine,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${date.year}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DiaryPalette.wine,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineEntryCard extends StatelessWidget {
  const _TimelineEntryCard({
    required this.entry,
    required this.rootDirectoryPath,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final DiaryEntry entry;
  final String? rootDirectoryPath;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: DiaryPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: DiaryPalette.ink,
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${formatDiaryDate(entry.createdAt)} ${formatDiaryTime(entry.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DiaryPalette.wine,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_EntryAction>(
                  onSelected: (action) {
                    if (action == _EntryAction.edit) {
                      onEdit();
                      return;
                    }
                    onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: _EntryAction.edit, child: Text('编辑')),
                    PopupMenuItem(
                      value: _EntryAction.delete,
                      child: Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              entry.summary,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: DiaryPalette.wine,
                height: 1.58,
              ),
            ),
            if (entry.attachments.isNotEmpty) ...[
              const SizedBox(height: 14),
              _TimelineEntryPreview(
                rootDirectoryPath: rootDirectoryPath,
                attachments: entry.attachments,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DiaryBadge(label: entry.author, tone: DiaryBadgeTone.sand),
                DiaryBadge(label: entry.mood),
                if (entry.attachments.isNotEmpty)
                  DiaryBadge(
                    label: '${entry.attachments.length} 张图',
                    tone: DiaryBadgeTone.sand,
                  ),
                if (entry.commentCount > 0)
                  DiaryBadge(
                    label: '${entry.commentCount} 条评论',
                    tone: DiaryBadgeTone.ink,
                  ),
                if (entry.updatedAt != null)
                  DiaryBadge(
                    label:
                        '更新 ${formatDiaryShortDate(entry.updatedAt!)} ${formatDiaryTime(entry.updatedAt!)}',
                    tone: DiaryBadgeTone.ink,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEntryPreview extends StatelessWidget {
  const _TimelineEntryPreview({
    required this.rootDirectoryPath,
    required this.attachments,
  });

  final String? rootDirectoryPath;
  final List<DiaryAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final previewAttachments = attachments.take(3).toList();
    final availableWidth = MediaQuery.sizeOf(context).width - 150;
    final tileSize = ((availableWidth - 16) / 3).clamp(56.0, 82.0).toDouble();
    return ClipRect(
      child: SizedBox(
        height: tileSize,
        child: Row(
          children: List.generate(previewAttachments.length, (index) {
            final remainingCount = attachments.length - 3;
            return Padding(
              padding: EdgeInsets.only(
                right: index == previewAttachments.length - 1 ? 0 : 8,
              ),
              child: SizedBox.square(
                dimension: tileSize,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DiaryCover(
                      rootDirectoryPath: rootDirectoryPath,
                      attachments: [previewAttachments[index]],
                      width: tileSize,
                      height: tileSize,
                      radius: 20,
                      fit: BoxFit.cover,
                      showShadow: false,
                    ),
                    if (index == 2 && remainingCount > 0)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: DiaryPalette.ink.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            '+$remainingCount',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: DiaryPalette.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

enum _EntryAction { edit, delete }
