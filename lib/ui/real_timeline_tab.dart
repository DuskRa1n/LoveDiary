import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import 'diary_design.dart';

class RealTimelineTab extends StatefulWidget {
  const RealTimelineTab({
    super.key,
    required this.entries,
    required this.rootDirectoryPath,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final List<DiaryEntry> entries;
  final String? rootDirectoryPath;
  final ValueChanged<DiaryEntry> onOpenEntry;
  final Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry;
  final Future<void> Function(DiaryEntry entry) onDeleteEntry;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这篇日记？'),
          content: Text('《${entry.title}》会先进入回收站，7 天内都还能恢复。'),
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
      final matchesMood =
          _selectedMood == null || entry.mood == _selectedMood;
      final matchesDate =
          _selectedDate == null || isSameDiaryDay(entry.createdAt, _selectedDate!);
      return matchesQuery && matchesMood && matchesDate;
    }).toList();

    return DiaryPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DiaryHero(
            eyebrow: '时间线',
            title: '所有日记',
            subtitle: '筛选和查看所有内容。',
            footer: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                DiaryBadge(label: '共 ${widget.entries.length} 篇'),
                if (_selectedMood != null)
                  DiaryBadge(
                    label: '心情 $_selectedMood',
                    tone: DiaryBadgeTone.sand,
                  ),
                if (_selectedDate != null)
                  DiaryBadge(
                    label: formatDiaryDate(_selectedDate!),
                    tone: DiaryBadgeTone.ink,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          DiaryPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DiarySectionHeader(
                  title: '筛选',
                  subtitle: '按关键词、心情和日期筛选。',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索标题或正文',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('全部心情'),
                      selected: _selectedMood == null,
                      onSelected: (_) {
                        setState(() {
                          _selectedMood = null;
                        });
                      },
                    ),
                    ...moods.map(
                      (mood) => FilterChip(
                        label: Text(mood),
                        selected: _selectedMood == mood,
                        onSelected: (_) {
                          setState(() {
                            _selectedMood = mood;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text(
                          _selectedDate == null
                              ? '选择日期'
                              : formatDiaryShortDate(_selectedDate!),
                        ),
                      ),
                    ),
                    if (query.isNotEmpty ||
                        _selectedMood != null ||
                        _selectedDate != null) ...[
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: _clearFilters,
                        child: const Text('清空'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          DiarySectionHeader(
            title: query.isEmpty && _selectedMood == null && _selectedDate == null
                ? '全部日记'
                : '筛选结果',
            subtitle: query.isEmpty && _selectedMood == null && _selectedDate == null
                ? '按时间倒序显示。'
                : '共 ${filteredEntries.length} 篇。',
          ),
          const SizedBox(height: 14),
          if (widget.entries.isEmpty)
            const DiaryEmptyState(
              title: '还没有日记',
              subtitle: '先写一篇。',
            )
          else if (filteredEntries.isEmpty)
            const DiaryEmptyState(
              title: '没有匹配结果',
              subtitle: '换个关键词，或者清空筛选条件。',
            )
          else
            ...filteredEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _TimelineEntryCard(
                  entry: entry,
                  rootDirectoryPath: widget.rootDirectoryPath,
                  onTap: () => widget.onOpenEntry(entry),
                  onEdit: () => widget.onEditEntry(entry),
                  onDelete: () => _confirmDelete(entry),
                ),
              ),
            ),
        ],
      ),
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
                Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: DiaryPalette.mist,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${entry.createdAt.day}',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: DiaryPalette.rose,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        '${entry.createdAt.month}月',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: DiaryPalette.wine,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: DiaryPalette.ink,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatDiaryDate(entry.createdAt)} ${formatDiaryTime(entry.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: DiaryPalette.wine,
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
                    PopupMenuItem(
                      value: _EntryAction.edit,
                      child: Text('编辑'),
                    ),
                    PopupMenuItem(
                      value: _EntryAction.delete,
                      child: Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    entry.summary,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: DiaryPalette.wine,
                          height: 1.55,
                        ),
                  ),
                ),
                if (entry.attachments.isNotEmpty) ...[
                  const SizedBox(width: 14),
                  DiaryCover(
                    rootDirectoryPath: rootDirectoryPath,
                    attachments: entry.attachments,
                    width: 96,
                    height: 118,
                    radius: 20,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DiaryBadge(label: entry.mood),
                DiaryBadge(
                  label: '${entry.attachments.length} 张图',
                  tone: DiaryBadgeTone.sand,
                ),
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

enum _EntryAction { edit, delete }
