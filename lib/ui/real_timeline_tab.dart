import 'dart:async';

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
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() {});
    });
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
        DiaryReveal(
          child: DiaryHero(
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
        ),
        const SizedBox(height: 22),
        DiaryReveal(
          delay: const Duration(milliseconds: 100),
          offset: const Offset(0, 0.06),
          child: _TimelineFilterPanel(
            controller: _searchController,
            moods: moods,
            selectedMood: _selectedMood,
            selectedDate: _selectedDate,
            hasFilter: hasFilter,
            onQueryChanged: _onSearchChanged,
            onMoodSelected: (mood) {
              setState(() {
                _selectedMood = mood;
              });
            },
            onPickDate: _pickDate,
            onClear: _clearFilters,
          ),
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
        return DiaryReveal(
          delay: Duration(milliseconds: 90 + (entryIndex.clamp(0, 5) * 45)),
          offset: const Offset(0, 0.08),
          child: _TimelineEntryRow(
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
          ),
        );
      },
    );
  }
}

class TimelineSection extends StatelessWidget {
  const TimelineSection({
    super.key,
    required this.entries,
    required this.rootDirectoryPath,
    required this.isWriteLocked,
    required this.onWriteBlocked,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final List<DiaryEntry> entries;
  final String? rootDirectoryPath;
  final bool isWriteLocked;
  final VoidCallback onWriteBlocked;
  final ValueChanged<DiaryEntry> onOpenEntry;
  final Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry;
  final Future<void> Function(DiaryEntry entry) onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          DiarySectionHeader(title: '时间轴'),
          SizedBox(height: 14),
          DiaryEmptyState(title: '还没有日记'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiarySectionHeader(title: '时间轴'),
        const SizedBox(height: 14),
        for (var index = 0; index < entries.length; index++)
          DiaryReveal(
            delay: Duration(milliseconds: 70 + (index.clamp(0, 5) * 38)),
            offset: const Offset(0, 0.06),
            child: _TimelineEntryRow(
              entry: entries[index],
              rootDirectoryPath: rootDirectoryPath,
              isFirst: index == 0,
              isLast: index == entries.length - 1,
              onTap: () => onOpenEntry(entries[index]),
              onEdit: () {
                if (isWriteLocked) {
                  onWriteBlocked();
                  return;
                }
                onEditEntry(entries[index]);
              },
              onDelete: () => _confirmTimelineDelete(
                context: context,
                entry: entries[index],
                isWriteLocked: isWriteLocked,
                onWriteBlocked: onWriteBlocked,
                onDeleteEntry: onDeleteEntry,
              ),
            ),
          ),
      ],
    );
  }
}

class TimelineSliverSection extends StatelessWidget {
  const TimelineSliverSection({
    super.key,
    required this.entries,
    required this.rootDirectoryPath,
    required this.isWriteLocked,
    required this.onWriteBlocked,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
    this.headerKey,
    this.padding = EdgeInsets.zero,
  });

  final List<DiaryEntry> entries;
  final String? rootDirectoryPath;
  final bool isWriteLocked;
  final VoidCallback onWriteBlocked;
  final ValueChanged<DiaryEntry> onOpenEntry;
  final Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry;
  final Future<void> Function(DiaryEntry entry) onDeleteEntry;
  final Key? headerKey;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return SliverPadding(
        padding: padding,
        sliver: SliverToBoxAdapter(
          child: KeyedSubtree(
            key: headerKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                DiarySectionHeader(title: '时间轴'),
                SizedBox(height: 14),
                DiaryEmptyState(title: '还没有日记'),
              ],
            ),
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(
            child: KeyedSubtree(
              key: headerKey,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DiarySectionHeader(title: '时间轴'),
                  SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: padding,
          sliver: SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return DiaryReveal(
                delay: Duration(milliseconds: 70 + (index.clamp(0, 5) * 38)),
                offset: const Offset(0, 0.06),
                child: _TimelineEntryRow(
                  entry: entry,
                  rootDirectoryPath: rootDirectoryPath,
                  isFirst: index == 0,
                  isLast: index == entries.length - 1,
                  onTap: () => onOpenEntry(entry),
                  onEdit: () {
                    if (isWriteLocked) {
                      onWriteBlocked();
                      return;
                    }
                    onEditEntry(entry);
                  },
                  onDelete: () => _confirmTimelineDelete(
                    context: context,
                    entry: entry,
                    isWriteLocked: isWriteLocked,
                    onWriteBlocked: onWriteBlocked,
                    onDeleteEntry: onDeleteEntry,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> showTimelineSearchPage({
  required BuildContext context,
  required List<DiaryEntry> entries,
  required String? rootDirectoryPath,
  required bool isWriteLocked,
  required VoidCallback onWriteBlocked,
  required ValueChanged<DiaryEntry> onOpenEntry,
  required Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry,
  required Future<void> Function(DiaryEntry entry) onDeleteEntry,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          TimelineSearchPage(
            entries: entries,
            rootDirectoryPath: rootDirectoryPath,
            isWriteLocked: isWriteLocked,
            onWriteBlocked: onWriteBlocked,
            onOpenEntry: onOpenEntry,
            onEditEntry: onEditEntry,
            onDeleteEntry: onDeleteEntry,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final reducedMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (reducedMotion) {
          return FadeTransition(opacity: animation, child: child);
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
    ),
  );
}

class TimelineSearchPage extends StatefulWidget {
  const TimelineSearchPage({
    super.key,
    required this.entries,
    required this.rootDirectoryPath,
    required this.isWriteLocked,
    required this.onWriteBlocked,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final List<DiaryEntry> entries;
  final String? rootDirectoryPath;
  final bool isWriteLocked;
  final VoidCallback onWriteBlocked;
  final ValueChanged<DiaryEntry> onOpenEntry;
  final Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry;
  final Future<void> Function(DiaryEntry entry) onDeleteEntry;

  @override
  State<TimelineSearchPage> createState() => _TimelineSearchPageState();
}

class _TimelineSearchPageState extends State<TimelineSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedMood;
  DateTime? _selectedDate;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() {});
      }
    });
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

  List<DiaryEntry> get _filteredEntries {
    final query = _searchController.text.trim().toLowerCase();
    return widget.entries.where((entry) {
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
  }

  @override
  Widget build(BuildContext context) {
    final moods = widget.entries.map((entry) => entry.mood).toSet().toList()
      ..sort();
    final filteredEntries = _filteredEntries;
    final hasFilter =
        _searchController.text.trim().isNotEmpty ||
        _selectedMood != null ||
        _selectedDate != null;
    final topPadding = MediaQuery.paddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const Positioned.fill(child: DiaryBackground()),
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(18, topPadding + 18, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: '返回',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '搜索日记',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: DiaryPalette.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _TimelineFilterPanel(
                        controller: _searchController,
                        moods: moods,
                        selectedMood: _selectedMood,
                        selectedDate: _selectedDate,
                        hasFilter: hasFilter,
                        onQueryChanged: _onSearchChanged,
                        onMoodSelected: (mood) {
                          setState(() {
                            _selectedMood = mood;
                          });
                        },
                        onPickDate: _pickDate,
                        onClear: _clearFilters,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.entries.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(18, 22, 18, 36),
                  sliver: SliverToBoxAdapter(
                    child: DiaryEmptyState(title: '还没有日记'),
                  ),
                )
              else if (filteredEntries.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(18, 22, 18, 36),
                  sliver: SliverToBoxAdapter(
                    child: DiaryEmptyState(title: '没有匹配结果'),
                  ),
                )
              else
                TimelineSliverSection(
                  entries: filteredEntries,
                  rootDirectoryPath: widget.rootDirectoryPath,
                  isWriteLocked: widget.isWriteLocked,
                  onWriteBlocked: widget.onWriteBlocked,
                  onOpenEntry: (entry) {
                    Navigator.of(context).pop();
                    widget.onOpenEntry(entry);
                  },
                  onEditEntry: widget.onEditEntry,
                  onDeleteEntry: widget.onDeleteEntry,
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 36),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmTimelineDelete({
  required BuildContext context,
  required DiaryEntry entry,
  required bool isWriteLocked,
  required VoidCallback onWriteBlocked,
  required Future<void> Function(DiaryEntry entry) onDeleteEntry,
}) async {
  if (isWriteLocked) {
    onWriteBlocked();
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

  if (confirmed == true) {
    await onDeleteEntry(entry);
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

  static const _radius = 24.0;
  static const _stripeWidth = 5.0;

  @override
  Widget build(BuildContext context) {
    final moodColor = _moodStripeColor(entry.mood);
    return InkWell(
      borderRadius: BorderRadius.circular(_radius),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: DiaryPalette.white.withValues(
            alpha: DiaryPalette.surfaceStrongAlpha,
          ),
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(
            color: DiaryPalette.white.withValues(
              alpha: DiaryPalette.surfaceBorderAlpha,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: DiaryPalette.rose.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _stripeWidth,
                  child: ColoredBox(color: moodColor),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: DiaryPalette.ink,
                                          fontWeight: FontWeight.w900,
                                          height: 1.2,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time_rounded,
                                        size: 13,
                                        color: DiaryPalette.wine.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${formatDiaryDate(entry.createdAt)} ${formatDiaryTime(entry.createdAt)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: DiaryPalette.wine,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<_EntryAction>(
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                color: DiaryPalette.wine.withValues(alpha: 0.5),
                                size: 20,
                              ),
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
                        const SizedBox(height: 12),
                        Text(
                          entry.summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: DiaryPalette.wine,
                                height: 1.65,
                              ),
                        ),
                        if (entry.attachments.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _TimelineEntryPreview(
                            rootDirectoryPath: rootDirectoryPath,
                            attachments: entry.attachments,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _MiniTag(
                              label: entry.author,
                              icon: Icons.person_rounded,
                            ),
                            _MiniTag(
                              label: entry.mood,
                              icon: Icons.favorite_rounded,
                            ),
                            if (entry.attachments.isNotEmpty)
                              _MiniTag(
                                label: '${entry.attachments.length}',
                                icon: Icons.image_rounded,
                              ),
                            if (entry.commentCount > 0)
                              _MiniTag(
                                label: '${entry.commentCount}',
                                icon: Icons.chat_bubble_rounded,
                              ),
                          ],
                        ),
                      ],
                    ),
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

Color _moodStripeColor(String mood) {
  return switch (mood) {
    '开心' => const Color(0xFFFF9B8E),
    '安心' => const Color(0xFF8EC5A0),
    '温柔' => const Color(0xFFF0B8D0),
    '想念' => const Color(0xFFB8A0E0),
    '真诚' => const Color(0xFFE0C070),
    '治愈' => const Color(0xFF80C8D8),
    '甜' => const Color(0xFFF0A0B8),
    '难过' => const Color(0xFF7B9EC8),
    '委屈' => const Color(0xFF9BA8C0),
    '生气' => const Color(0xFFD08080),
    '焦虑' => const Color(0xFFC8A870),
    '孤独' => const Color(0xFF8CA0B8),
    '失落' => const Color(0xFFA0A8B8),
    _ => DiaryPalette.rose,
  };
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: DiaryPalette.mist.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: DiaryPalette.rose.withValues(alpha: 0.7)),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: DiaryPalette.wine,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
