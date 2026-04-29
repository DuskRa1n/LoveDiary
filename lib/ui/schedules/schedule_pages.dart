part of '../../app.dart';

class ScheduleManagerPage extends StatefulWidget {
  const ScheduleManagerPage({
    super.key,
    required this.schedules,
    required this.initialDate,
    required this.writeLockedListenable,
    required this.onWriteBlocked,
    required this.onSaveSchedule,
    required this.onDeleteSchedule,
  });

  final List<ScheduleItem> schedules;
  final DateTime? initialDate;
  final ValueListenable<bool> writeLockedListenable;
  final VoidCallback onWriteBlocked;
  final Future<void> Function(ScheduleItem schedule) onSaveSchedule;
  final Future<void> Function(ScheduleItem schedule) onDeleteSchedule;

  @override
  State<ScheduleManagerPage> createState() => _ScheduleManagerPageState();
}

class _ScheduleManagerPageState extends State<ScheduleManagerPage> {
  late DateTime _selectedDate;
  late List<ScheduleItem> _schedules;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = _scheduleDateOnly(widget.initialDate ?? DateTime.now());
    _schedules = List<ScheduleItem>.from(widget.schedules);
  }

  Future<void> _openEditor({ScheduleItem? schedule, DateTime? date}) async {
    if (widget.writeLockedListenable.value) {
      widget.onWriteBlocked();
      return;
    }

    final result = await Navigator.of(context).push<ScheduleItem>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScheduleEditorPage(
          initialSchedule: schedule,
          initialDate: date ?? _selectedDate,
          writeLockedListenable: widget.writeLockedListenable,
          onWriteBlocked: widget.onWriteBlocked,
        ),
      ),
    );
    if (result == null) {
      return;
    }

    await widget.onSaveSchedule(result);
    if (!mounted) {
      return;
    }
    setState(() {
      final index = _schedules.indexWhere((item) => item.id == result.id);
      if (index == -1) {
        _schedules = [result, ..._schedules]..sort(_compareScheduleItems);
      } else {
        _schedules[index] = result;
        _schedules.sort(_compareScheduleItems);
      }
      _hasChanged = true;
    });
  }

  Future<void> _deleteSchedule(ScheduleItem schedule) async {
    if (widget.writeLockedListenable.value) {
      widget.onWriteBlocked();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这个日程？'),
          content: Text('「${schedule.title}」会从日程表中移除。'),
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

    await widget.onDeleteSchedule(schedule);
    if (!mounted) {
      return;
    }
    setState(() {
      _schedules = [
        for (final item in _schedules)
          if (item.id != schedule.id) item,
      ];
      _hasChanged = true;
    });
  }

  Future<bool> _handlePop() async {
    Navigator.of(context).pop(_hasChanged);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final monthOccurrences = _scheduleOccurrencesForMonth(
      schedules: _schedules,
      month: _selectedDate,
    );
    final selectedOccurrences = monthOccurrences
        .where((item) => isSameDay(item.date, _selectedDate))
        .toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handlePop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: DiaryPalette.paper.withValues(alpha: 0.96),
          surfaceTintColor: Colors.transparent,
          title: const Text('日程表'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(_hasChanged),
          ),
          actions: [
            IconButton(
              tooltip: '添加日程',
              onPressed: () => _openEditor(date: _selectedDate),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        body: DiaryPage(
          respectTopSafeArea: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DiaryCompactHeader(
                eyebrow: '日程',
                title: formatDiaryDate(_selectedDate),
                footer: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DiaryBadge(label: '${monthOccurrences.length} 个日程'),
                    DiaryBadge(
                      label: _monthScheduleLabel(_selectedDate),
                      tone: DiaryBadgeTone.sand,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _ScheduleDatePickerPanel(
                selectedDate: _selectedDate,
                onChanged: (date) {
                  setState(() {
                    _selectedDate = date;
                  });
                },
              ),
              const SizedBox(height: 18),
              const DiarySectionHeader(title: '这一天'),
              const SizedBox(height: 12),
              if (selectedOccurrences.isEmpty)
                DiaryEmptyState(title: '还没有日程', icon: Icons.event_note_rounded)
              else
                ...selectedOccurrences.map(
                  (occurrence) => _ScheduleTile(
                    occurrence: occurrence,
                    onEdit: () => _openEditor(schedule: occurrence.item),
                    onDelete: () => _deleteSchedule(occurrence.item),
                  ),
                ),
              const SizedBox(height: 20),
              const DiarySectionHeader(title: '本月日程'),
              const SizedBox(height: 12),
              if (monthOccurrences.isEmpty)
                const DiaryEmptyState(
                  title: '本月没有日程',
                  icon: Icons.calendar_month_rounded,
                )
              else
                ...monthOccurrences.map(
                  (occurrence) => _ScheduleTile(
                    occurrence: occurrence,
                    onTap: () {
                      setState(() {
                        _selectedDate = occurrence.date;
                      });
                    },
                    onEdit: () => _openEditor(schedule: occurrence.item),
                    onDelete: () => _deleteSchedule(occurrence.item),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScheduleEditorPage extends StatefulWidget {
  const ScheduleEditorPage({
    super.key,
    this.initialSchedule,
    this.initialDate,
    required this.writeLockedListenable,
    required this.onWriteBlocked,
  });

  final ScheduleItem? initialSchedule;
  final DateTime? initialDate;
  final ValueListenable<bool> writeLockedListenable;
  final VoidCallback onWriteBlocked;

  @override
  State<ScheduleEditorPage> createState() => _ScheduleEditorPageState();
}

class _ScheduleEditorPageState extends State<ScheduleEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late ScheduleItemType _type;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final schedule = widget.initialSchedule;
    _titleController = TextEditingController(text: schedule?.title ?? '');
    _descriptionController = TextEditingController(
      text: schedule?.description ?? '',
    );
    _type = schedule?.type ?? ScheduleItemType.oneTime;
    _selectedDate = _scheduleDateOnly(
      schedule?.date ?? widget.initialDate ?? DateTime.now(),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
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
      _selectedDate = _scheduleDateOnly(picked);
    });
  }

  void _submit() {
    if (widget.writeLockedListenable.value) {
      widget.onWriteBlocked();
      return;
    }

    late final String title;
    try {
      title = ScheduleItem.normalizeTitle(_titleController.text);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    final now = DateTime.now();
    final initial = widget.initialSchedule;
    final description = _descriptionController.text.trim();
    Navigator.of(context).pop(
      ScheduleItem(
        id: initial?.id ?? 'schedule_${now.microsecondsSinceEpoch}',
        title: title,
        description: description.isEmpty ? null : description,
        date: _selectedDate,
        type: _type,
        createdAt: initial?.createdAt ?? now,
        updatedAt: initial == null ? null : now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialSchedule != null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: DiaryPalette.paper.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        title: Text(isEditing ? '编辑日程' : '添加日程'),
        actions: [
          TextButton(onPressed: _submit, child: const Text('保存')),
          const SizedBox(width: 6),
        ],
      ),
      body: DiaryPage(
        respectTopSafeArea: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DiaryCompactHeader(
              eyebrow: '日程',
              title: isEditing ? '编辑重要日子' : '记录一个安排',
              footer: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DiaryBadge(label: _scheduleTypeLabel(_type)),
                  DiaryBadge(
                    label: _scheduleDateLabel(_type, _selectedDate),
                    tone: DiaryBadgeTone.sand,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            DiaryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      hintText: '他的生日',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '描述（可选）',
                      hintText: '准备礼物、订餐、行程备注...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('单次行程'),
                        selected: _type == ScheduleItemType.oneTime,
                        onSelected: (_) {
                          setState(() {
                            _type = ScheduleItemType.oneTime;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('每年重复'),
                        selected: _type == ScheduleItemType.yearly,
                        onSelected: (_) {
                          setState(() {
                            _type = ScheduleItemType.yearly;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_type == ScheduleItemType.oneTime)
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text('日期：${formatDiaryDate(_selectedDate)}'),
                    )
                  else
                    _ScheduleMonthDayFields(
                      selectedDate: _selectedDate,
                      onChanged: (date) {
                        setState(() {
                          _selectedDate = date;
                        });
                      },
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('保存日程'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleDatePickerPanel extends StatelessWidget {
  const _ScheduleDatePickerPanel({
    required this.selectedDate,
    required this.onChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final startYear = math.min(2000, selectedDate.year);
    final endYear = math.max(2100, selectedDate.year);
    final daysInMonth = _lastScheduleDayOfMonth(
      selectedDate.year,
      selectedDate.month,
    );

    return DiaryPanel(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth >= 390
              ? (constraints.maxWidth - 16) / 3
              : (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              SizedBox(
                width: fieldWidth,
                child: _ScheduleDropdown<int>(
                  label: '年',
                  value: selectedDate.year,
                  items: [
                    for (var year = startYear; year <= endYear; year++) year,
                  ],
                  itemLabel: (year) => '$year',
                  onChanged: (year) {
                    onChanged(
                      _clampedScheduleDate(
                        year: year,
                        month: selectedDate.month,
                        day: selectedDate.day,
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _ScheduleDropdown<int>(
                  label: '月',
                  value: selectedDate.month,
                  items: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                  itemLabel: (month) => '$month月',
                  onChanged: (month) {
                    onChanged(
                      _clampedScheduleDate(
                        year: selectedDate.year,
                        month: month,
                        day: selectedDate.day,
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _ScheduleDropdown<int>(
                  label: '日',
                  value: selectedDate.day.clamp(1, daysInMonth).toInt(),
                  items: [for (var day = 1; day <= daysInMonth; day++) day],
                  itemLabel: (day) => '$day日',
                  onChanged: (day) {
                    onChanged(
                      _clampedScheduleDate(
                        year: selectedDate.year,
                        month: selectedDate.month,
                        day: day,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScheduleMonthDayFields extends StatelessWidget {
  const _ScheduleMonthDayFields({
    required this.selectedDate,
    required this.onChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = _lastScheduleDayOfMonth(
      selectedDate.year,
      selectedDate.month,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.maxWidth >= 340
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: fieldWidth,
              child: _ScheduleDropdown<int>(
                label: '每年月份',
                value: selectedDate.month,
                items: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                itemLabel: (month) => '$month月',
                onChanged: (month) {
                  onChanged(
                    _clampedScheduleDate(
                      year: selectedDate.year,
                      month: month,
                      day: selectedDate.day,
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: _ScheduleDropdown<int>(
                label: '日期',
                value: selectedDate.day.clamp(1, daysInMonth).toInt(),
                items: [for (var day = 1; day <= daysInMonth; day++) day],
                itemLabel: (day) => '$day日',
                onChanged: (day) {
                  onChanged(
                    _clampedScheduleDate(
                      year: selectedDate.year,
                      month: selectedDate.month,
                      day: day,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScheduleDropdown<T> extends StatelessWidget {
  const _ScheduleDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T item) itemLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
      ],
      onChanged: (item) {
        if (item != null) {
          onChanged(item);
        }
      },
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.occurrence,
    this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final _ScheduleOccurrence occurrence;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final item = occurrence.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: DiaryPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DiaryPalette.mist,
                  shape: BoxShape.circle,
                  border: Border.all(color: DiaryPalette.white),
                ),
                alignment: Alignment.center,
                child: Icon(
                  item.type == ScheduleItemType.yearly
                      ? Icons.cake_rounded
                      : Icons.event_available_rounded,
                  color: DiaryPalette.rose,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: DiaryPalette.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatDiaryDate(occurrence.date)} · ${_scheduleTypeLabel(item.type)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DiaryPalette.wine,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.description?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.description!.trim(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: DiaryPalette.wine,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<_ScheduleAction>(
                onSelected: (action) {
                  switch (action) {
                    case _ScheduleAction.edit:
                      onEdit();
                      break;
                    case _ScheduleAction.delete:
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _ScheduleAction.edit, child: Text('编辑')),
                  PopupMenuItem(
                    value: _ScheduleAction.delete,
                    child: Text('删除'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ScheduleAction { edit, delete }

class _ScheduleOccurrence {
  const _ScheduleOccurrence({required this.item, required this.date});

  final ScheduleItem item;
  final DateTime date;
}

List<_ScheduleOccurrence> _scheduleOccurrencesForMonth({
  required List<ScheduleItem> schedules,
  required DateTime month,
}) {
  final monthStart = DateTime(month.year, month.month);
  final monthEnd = DateTime(month.year, month.month + 1, 0);
  final occurrences = <_ScheduleOccurrence>[];
  for (final schedule in schedules) {
    final occurrence = schedule.occurrenceInYear(month.year);
    if (schedule.type == ScheduleItemType.oneTime &&
        schedule.date.year != month.year) {
      continue;
    }
    if (occurrence.isBefore(monthStart) || occurrence.isAfter(monthEnd)) {
      continue;
    }
    occurrences.add(_ScheduleOccurrence(item: schedule, date: occurrence));
  }
  occurrences.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) {
      return byDate;
    }
    return a.item.title.compareTo(b.item.title);
  });
  return occurrences;
}

int _compareScheduleItems(ScheduleItem a, ScheduleItem b) {
  final byDate = a.date.compareTo(b.date);
  if (byDate != 0) {
    return byDate;
  }
  return a.title.compareTo(b.title);
}

DateTime _scheduleDateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

int _lastScheduleDayOfMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

DateTime _clampedScheduleDate({
  required int year,
  required int month,
  required int day,
}) {
  final lastDay = _lastScheduleDayOfMonth(year, month);
  return DateTime(year, month, day.clamp(1, lastDay).toInt());
}

String _scheduleTypeLabel(ScheduleItemType type) {
  return switch (type) {
    ScheduleItemType.oneTime => '单次行程',
    ScheduleItemType.yearly => '每年重复',
  };
}

String _scheduleDateLabel(ScheduleItemType type, DateTime date) {
  return switch (type) {
    ScheduleItemType.oneTime => formatDiaryDate(date),
    ScheduleItemType.yearly => '每年 ${date.month}月${date.day}日',
  };
}

String _monthScheduleLabel(DateTime date) {
  return '${date.year}年${date.month}月';
}
