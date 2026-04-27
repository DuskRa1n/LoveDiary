import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import 'diary_design.dart';

class RealTodayTab extends StatelessWidget {
  const RealTodayTab({
    super.key,
    required this.profile,
    required this.entries,
    required this.startupQuote,
  });

  final CoupleProfile profile;
  final List<DiaryEntry> entries;
  final String startupQuote;

  @override
  Widget build(BuildContext context) {
    final togetherDays =
        DateTime.now().difference(profile.togetherSince).inDays + 1;

    return DiaryPage(
      showBackground: false,
      respectTopSafeArea: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DiaryHero(
            eyebrow: '首页',
            title: '${profile.currentUserName} 和 ${profile.partnerName}',
            subtitle: '恋爱空间',
            trailing: _DaysSeal(days: togetherDays),
            quote: startupQuote,
            footer: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                DiaryBadge(label: '在一起 $togetherDays 天'),
                DiaryBadge(
                  label: '${entries.length} 篇日记',
                  tone: DiaryBadgeTone.ink,
                ),
                DiaryBadge(
                  label: '纪念日 ${formatDiaryShortDate(profile.togetherSince)}',
                  tone: DiaryBadgeTone.sand,
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _MoodSummaryPanel(entries: entries),
          const SizedBox(height: 18),
          _DiaryHeatmapPanel(entries: entries),
        ],
      ),
    );
  }
}

class _MoodSummaryPanel extends StatelessWidget {
  const _MoodSummaryPanel({required this.entries});

  final List<DiaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recentEntries = entries
        .where((entry) => !entry.createdAt.isBefore(cutoff))
        .toList();
    final moodCounts = <String, int>{};
    for (final entry in recentEntries) {
      moodCounts.update(entry.mood, (count) => count + 1, ifAbsent: () => 1);
    }
    final topMoods = moodCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) {
          return byCount;
        }
        return a.key.compareTo(b.key);
      });

    final dominantMood = topMoods.isEmpty ? '还没有' : topMoods.first.key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiaryPanel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: topMoods.isEmpty
              ? const DiaryEmptyState(
                  title: '还没有心情统计',
                  subtitle: '写下日记后，这里会自动汇总最近 30 天的心情分布。',
                  icon: Icons.favorite_border_rounded,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '最近心情',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: DiaryPalette.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        Text(
                          '近 30 天 · ${recentEntries.length} 篇',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: DiaryPalette.wine,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '最常出现的是「$dominantMood」。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DiaryPalette.wine,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (
                          var index = 0;
                          index < topMoods.take(8).length;
                          index++
                        )
                          _MoodCountChip(
                            mood: topMoods[index].key,
                            count: topMoods[index].value,
                            colors: _moodColors(index),
                            highlighted: topMoods[index].key == dominantMood,
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MoodCountChip extends StatelessWidget {
  const _MoodCountChip({
    required this.mood,
    required this.count,
    required this.colors,
    required this.highlighted,
  });

  final String mood;
  final int count;
  final _MoodColors colors;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border, width: highlighted ? 1.3 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mood,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: DiaryPalette.white.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodColors {
  const _MoodColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

_MoodColors _moodColors(int index) {
  const colors = [
    _MoodColors(
      background: Color(0xFFFFE4DF),
      foreground: Color(0xFFD97862),
      border: Color(0xFFF1BBAF),
    ),
    _MoodColors(
      background: Color(0xFFFFF0D2),
      foreground: Color(0xFFB87C50),
      border: Color(0xFFE8C48E),
    ),
    _MoodColors(
      background: Color(0xFFE7F3E8),
      foreground: Color(0xFF5E8B65),
      border: Color(0xFFB6D5BB),
    ),
    _MoodColors(
      background: Color(0xFFE8EFFA),
      foreground: Color(0xFF607CA8),
      border: Color(0xFFB9C9E2),
    ),
    _MoodColors(
      background: Color(0xFFF4E8F5),
      foreground: Color(0xFF9A6B9D),
      border: Color(0xFFD7B9DA),
    ),
    _MoodColors(
      background: Color(0xFFFFE8D8),
      foreground: Color(0xFFC06F44),
      border: Color(0xFFF0C0A5),
    ),
  ];
  return colors[index % colors.length];
}

class _DiaryHeatmapPanel extends StatefulWidget {
  const _DiaryHeatmapPanel({required this.entries});

  final List<DiaryEntry> entries;

  @override
  State<_DiaryHeatmapPanel> createState() => _DiaryHeatmapPanelState();
}

class _DiaryHeatmapPanelState extends State<_DiaryHeatmapPanel> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  DateTime get _currentMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  bool get _canGoNext => _visibleMonth.isBefore(_currentMonth);

  void _changeMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    if (next.isAfter(_currentMonth)) {
      return;
    }
    setState(() {
      _visibleMonth = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month);
    final monthEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
    final countsByDay = <DateTime, int>{};
    for (final entry in widget.entries) {
      final day = _dateOnly(entry.createdAt);
      if (day.isBefore(monthStart) || day.isAfter(monthEnd)) {
        continue;
      }
      countsByDay.update(day, (count) => count + 1, ifAbsent: () => 1);
    }
    final activeDays = countsByDay.length;
    final totalEntries = countsByDay.values.fold<int>(
      0,
      (total, count) => total + count,
    );
    final maxCount = countsByDay.values.fold<int>(
      0,
      (max, count) => count > max ? count : max,
    );

    final subtitle = totalEntries == 0
        ? '${_monthLabel(_visibleMonth)} 还没有日记记录。'
        : '${_monthLabel(_visibleMonth)} 有 $activeDays 天写过，共 $totalEntries 篇。';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DiarySectionHeader(title: '日记热力图', subtitle: subtitle),
        const SizedBox(height: 14),
        DiaryPanel(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 260) {
                _changeMonth(-1);
              } else if (velocity < -260) {
                _changeMonth(1);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '上个月',
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _monthLabel(_visibleMonth),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: DiaryPalette.ink,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '下个月',
                      onPressed: _canGoNext ? () => _changeMonth(1) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _MonthHeatmapGrid(
                  monthStart: monthStart,
                  today: today,
                  countsByDay: countsByDay,
                  maxCount: maxCount,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '左右滑动切换月份',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DiaryPalette.wine,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '少',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DiaryPalette.wine,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    for (var level = 0; level <= 4; level++) ...[
                      _HeatmapCell(color: _heatColor(level)),
                      if (level < 4) const SizedBox(width: 4),
                    ],
                    const SizedBox(width: 6),
                    const Text(
                      '多',
                      style: TextStyle(
                        color: DiaryPalette.wine,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthHeatmapGrid extends StatelessWidget {
  const _MonthHeatmapGrid({
    required this.monthStart,
    required this.today,
    required this.countsByDay,
    required this.maxCount,
  });

  final DateTime monthStart;
  final DateTime today;
  final Map<DateTime, int> countsByDay;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
    final leadingBlankDays = monthStart.weekday - DateTime.monday;
    final dayCount = monthEnd.day;
    final cellCount = ((leadingBlankDays + dayCount + 6) ~/ 7) * 7;

    return Column(
      children: [
        Row(
          children: [
            for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: DiaryPalette.wine,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: cellCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemBuilder: (context, index) {
            final dayNumber = index - leadingBlankDays + 1;
            if (dayNumber < 1 || dayNumber > dayCount) {
              return const SizedBox.shrink();
            }
            final day = DateTime(monthStart.year, monthStart.month, dayNumber);
            final count = countsByDay[day] ?? 0;
            final level = _heatLevel(count, maxCount);
            final isFuture = day.isAfter(today);
            return _MonthHeatmapCell(
              day: dayNumber,
              count: count,
              color: isFuture
                  ? DiaryPalette.line.withValues(alpha: 0.24)
                  : _heatColor(level),
            );
          },
        ),
      ],
    );
  }
}

class _MonthHeatmapCell extends StatelessWidget {
  const _MonthHeatmapCell({
    required this.day,
    required this.count,
    required this.color,
  });

  final int day;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: DiaryPalette.white.withValues(alpha: 0.62)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active ? DiaryPalette.white : DiaryPalette.wine,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          if (active) ...[
            const SizedBox(height: 2),
            Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: DiaryPalette.white.withValues(alpha: 0.90),
                fontWeight: FontWeight.w800,
                height: 1,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: DiaryPalette.white.withValues(alpha: 0.52)),
      ),
    );
  }
}

int _heatLevel(int count, int maxCount) {
  if (count <= 0 || maxCount <= 0) {
    return 0;
  }
  if (count == 1) {
    return 1;
  }
  final ratio = count / maxCount;
  if (ratio >= 0.75) {
    return 4;
  }
  if (ratio >= 0.5) {
    return 3;
  }
  return 2;
}

Color _heatColor(int level) {
  return switch (level) {
    0 => DiaryPalette.line.withValues(alpha: 0.42),
    1 => const Color(0xFFFFE0D9),
    2 => const Color(0xFFF6B7A9),
    3 => DiaryPalette.rose,
    _ => const Color(0xFFA94E3E),
  };
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _monthLabel(DateTime month) => '${month.year}年${month.month}月';

class _DaysSeal extends StatelessWidget {
  const _DaysSeal({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: DiaryPalette.mist.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        border: Border.all(color: DiaryPalette.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$days',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: DiaryPalette.rose,
              fontWeight: FontWeight.w900,
              height: 0.95,
            ),
          ),
          Text(
            '天',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: DiaryPalette.wine,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
