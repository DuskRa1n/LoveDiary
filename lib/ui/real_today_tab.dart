import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import 'diary_design.dart';

class RealTodayTab extends StatelessWidget {
  const RealTodayTab({
    super.key,
    required this.profile,
    required this.entries,
    required this.schedules,
    required this.startupQuote,
    required this.onOpenSchedules,
    this.topContentInset = 0,
  });

  final CoupleProfile profile;
  final List<DiaryEntry> entries;
  final List<ScheduleItem> schedules;
  final String startupQuote;
  final ValueChanged<DateTime> onOpenSchedules;
  final double topContentInset;

  @override
  Widget build(BuildContext context) {
    final togetherDays =
        DateTime.now().difference(profile.togetherSince).inDays + 1;

    return DiaryPage(
      showBackground: false,
      respectTopSafeArea: true,
      padding: EdgeInsets.fromLTRB(18, 14 + topContentInset, 18, 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DiaryHero(
            eyebrow: '首页',
            title: '${profile.currentUserName} 和 ${profile.partnerName}',
            trailing: _DaysSeal(days: togetherDays),
            quote: startupQuote,
            footer: _HeroFooter(
              anniversary: profile.togetherSince,
              entries: entries,
              schedules: schedules,
            ),
          ),
          const SizedBox(height: 22),
          _DiaryHeatmapPanel(
            entries: entries,
            schedules: schedules,
            onOpenSchedules: onOpenSchedules,
          ),
        ],
      ),
    );
  }
}

class _HeroFooter extends StatefulWidget {
  const _HeroFooter({
    required this.anniversary,
    required this.entries,
    required this.schedules,
  });

  final DateTime anniversary;
  final List<DiaryEntry> entries;
  final List<ScheduleItem> schedules;

  @override
  State<_HeroFooter> createState() => _HeroFooterState();
}

class _HeroFooterState extends State<_HeroFooter> {
  List<DiaryEntry>? _cachedEntries;
  int? _cachedEntryCount;
  List<MapEntry<String, int>> _cachedTopMoods = const [];

  List<MapEntry<String, int>> get _topMoods {
    if (identical(_cachedEntries, widget.entries) &&
        _cachedEntryCount == widget.entries.length) {
      return _cachedTopMoods;
    }

    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final moodCounts = <String, int>{};
    for (final entry in widget.entries) {
      if (entry.createdAt.isBefore(cutoff)) {
        continue;
      }
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

    _cachedEntries = widget.entries;
    _cachedEntryCount = widget.entries.length;
    _cachedTopMoods = topMoods;
    return topMoods;
  }

  @override
  Widget build(BuildContext context) {
    final topMoods = _topMoods;
    final upcomingSchedule = _nearestUpcomingSchedule(widget.schedules);
    final moodChips = [
      for (var index = 0; index < topMoods.take(6).length; index++)
        _MoodChip(mood: topMoods[index].key, colors: _moodColors(index)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DiaryBadge(label: _englishMonthDay(widget.anniversary)),
            if (upcomingSchedule != null)
              DiaryBadge(
                label:
                    '${upcomingSchedule.item.title}·${_distanceLabel(upcomingSchedule.daysAway)}',
                tone: DiaryBadgeTone.sand,
              ),
          ],
        ),
        if (moodChips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: moodChips),
        ],
      ],
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.mood, required this.colors});

  final String mood;
  final _MoodColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        mood,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
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
  const _DiaryHeatmapPanel({
    required this.entries,
    required this.schedules,
    required this.onOpenSchedules,
  });

  final List<DiaryEntry> entries;
  final List<ScheduleItem> schedules;
  final ValueChanged<DateTime> onOpenSchedules;

  @override
  State<_DiaryHeatmapPanel> createState() => _DiaryHeatmapPanelState();
}

class _DiaryHeatmapPanelState extends State<_DiaryHeatmapPanel> {
  late DateTime _visibleMonth;
  List<DiaryEntry>? _cachedEntries;
  int? _cachedEntryCount;
  List<ScheduleItem>? _cachedSchedules;
  int? _cachedScheduleCount;
  DateTime? _cachedMonth;
  _MonthHeatmapData _cachedMonthData = const _MonthHeatmapData(
    countsByDay: {},
    scheduleDays: {},
    maxCount: 0,
  );

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

  _MonthHeatmapData _dataForMonth(DateTime monthStart) {
    if (identical(_cachedEntries, widget.entries) &&
        _cachedEntryCount == widget.entries.length &&
        identical(_cachedSchedules, widget.schedules) &&
        _cachedScheduleCount == widget.schedules.length &&
        _cachedMonth == monthStart) {
      return _cachedMonthData;
    }

    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
    final countsByDay = <DateTime, int>{};
    for (final entry in widget.entries) {
      final day = _dateOnly(entry.createdAt);
      if (day.isBefore(monthStart) || day.isAfter(monthEnd)) {
        continue;
      }
      countsByDay.update(day, (count) => count + 1, ifAbsent: () => 1);
    }

    final maxCount = countsByDay.values.fold<int>(
      0,
      (max, count) => count > max ? count : max,
    );
    final scheduleDays = _scheduleDaysInMonth(
      schedules: widget.schedules,
      monthStart: monthStart,
    );
    final data = _MonthHeatmapData(
      countsByDay: Map.unmodifiable(countsByDay),
      scheduleDays: scheduleDays,
      maxCount: maxCount,
    );

    _cachedEntries = widget.entries;
    _cachedEntryCount = widget.entries.length;
    _cachedSchedules = widget.schedules;
    _cachedScheduleCount = widget.schedules.length;
    _cachedMonth = monthStart;
    _cachedMonthData = data;
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month);
    final monthData = _dataForMonth(monthStart);

    return DiaryPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                  visualDensity: VisualDensity.compact,
                  tooltip: '上个月',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      _monthLabel(_visibleMonth),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: DiaryPalette.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '下个月',
                  onPressed: _canGoNext ? () => _changeMonth(1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _MonthHeatmapGrid(
              monthStart: monthStart,
              today: today,
              countsByDay: monthData.countsByDay,
              scheduleDays: monthData.scheduleDays,
              maxCount: monthData.maxCount,
              onDaySelected: widget.onOpenSchedules,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeatmapData {
  const _MonthHeatmapData({
    required this.countsByDay,
    required this.scheduleDays,
    required this.maxCount,
  });

  final Map<DateTime, int> countsByDay;
  final Set<DateTime> scheduleDays;
  final int maxCount;
}

class _MonthHeatmapGrid extends StatelessWidget {
  const _MonthHeatmapGrid({
    required this.monthStart,
    required this.today,
    required this.countsByDay,
    required this.scheduleDays,
    required this.maxCount,
    required this.onDaySelected,
  });

  final DateTime monthStart;
  final DateTime today;
  final Map<DateTime, int> countsByDay;
  final Set<DateTime> scheduleDays;
  final int maxCount;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
    final leadingBlankDays = monthStart.weekday - DateTime.monday;
    final dayCount = monthEnd.day;
    final cellCount = ((leadingBlankDays + dayCount + 6) ~/ 7) * 7;

    final cellSize = MediaQuery.sizeOf(context).width >= 390 ? 32.0 : 30.0;

    return Center(
      child: SizedBox(
        width: cellSize * 7 + 5 * 6,
        child: Column(
          children: [
            Row(
              children: [
                for (var index = 0; index < 7; index++) ...[
                  SizedBox(
                    width: cellSize,
                    child: Text(
                      const ['一', '二', '三', '四', '五', '六', '日'][index],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: DiaryPalette.wine,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (index < 6) const SizedBox(width: 5),
                ],
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: cellCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - leadingBlankDays + 1;
                if (dayNumber < 1 || dayNumber > dayCount) {
                  return const SizedBox.shrink();
                }
                final day = DateTime(
                  monthStart.year,
                  monthStart.month,
                  dayNumber,
                );
                final count = countsByDay[day] ?? 0;
                final level = _heatLevel(count, maxCount);
                final isFuture = day.isAfter(today);
                return InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => onDaySelected(day),
                  child: _MonthHeatmapCell(
                    day: dayNumber,
                    active: !isFuture && count > 0,
                    hasSchedule: scheduleDays.contains(day),
                    color: isFuture
                        ? DiaryPalette.line.withValues(alpha: 0.24)
                        : _heatColor(level),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeatmapCell extends StatelessWidget {
  const _MonthHeatmapCell({
    required this.day,
    required this.active,
    required this.hasSchedule,
    required this.color,
  });

  final int day;
  final bool active;
  final bool hasSchedule;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
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
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: hasSchedule ? 4 : 0,
            height: hasSchedule ? 4 : 0,
            decoration: BoxDecoration(
              color: active ? DiaryPalette.white : DiaryPalette.rose,
              shape: BoxShape.circle,
            ),
          ),
        ],
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
    0 => const Color(0xFFF4E7DD),
    1 => const Color(0xFFFFD9D1),
    2 => const Color(0xFFF5A99A),
    3 => const Color(0xFFD97862),
    _ => const Color(0xFF9F4638),
  };
}

_UpcomingSchedule? _nearestUpcomingSchedule(List<ScheduleItem> schedules) {
  final today = _dateOnly(DateTime.now());
  const window = Duration(days: 15);
  _UpcomingSchedule? nearest;

  for (final schedule in schedules) {
    final occurrence = schedule.nextOccurrenceOnOrAfter(today);
    final daysAway = occurrence.difference(today).inDays;
    if (daysAway < 0 || daysAway > window.inDays) {
      continue;
    }
    final candidate = _UpcomingSchedule(
      item: schedule,
      occurrence: occurrence,
      daysAway: daysAway,
    );
    if (nearest == null ||
        candidate.occurrence.isBefore(nearest.occurrence) ||
        (candidate.occurrence == nearest.occurrence &&
            candidate.item.title.compareTo(nearest.item.title) < 0)) {
      nearest = candidate;
    }
  }
  return nearest;
}

Set<DateTime> _scheduleDaysInMonth({
  required List<ScheduleItem> schedules,
  required DateTime monthStart,
}) {
  final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
  return {
    for (final schedule in schedules)
      if (_occurrenceForMonth(schedule, monthStart) case final occurrence?)
        if (!occurrence.isBefore(monthStart) && !occurrence.isAfter(monthEnd))
          occurrence,
  };
}

DateTime? _occurrenceForMonth(ScheduleItem schedule, DateTime monthStart) {
  final occurrence = schedule.occurrenceInYear(monthStart.year);
  if (schedule.type == ScheduleItemType.oneTime &&
      schedule.date.year != monthStart.year) {
    return null;
  }
  if (occurrence.month != monthStart.month) {
    return null;
  }
  return occurrence;
}

String _distanceLabel(int daysAway) {
  if (daysAway == 0) {
    return '今天';
  }
  return '$daysAway天后';
}

class _UpcomingSchedule {
  const _UpcomingSchedule({
    required this.item,
    required this.occurrence,
    required this.daysAway,
  });

  final ScheduleItem item;
  final DateTime occurrence;
  final int daysAway;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _monthLabel(DateTime month) => '${month.year}年${month.month}月';

String _englishMonthDay(DateTime date) {
  const months = [
    'Jan.',
    'Feb.',
    'Mar.',
    'Apr.',
    'May',
    'Jun.',
    'Jul.',
    'Aug.',
    'Sep.',
    'Oct.',
    'Nov.',
    'Dec.',
  ];
  return '${months[date.month - 1]} ${date.day}${_ordinalSuffix(date.day)}';
}

String _ordinalSuffix(int day) {
  if (day >= 11 && day <= 13) {
    return 'th';
  }
  return switch (day % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
}

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
