import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/diary_models.dart';
import 'diary_design.dart';
import 'real_timeline_tab.dart';
import 'real_today_tab.dart';

class RealHomeFlowPage extends StatefulWidget {
  const RealHomeFlowPage({
    super.key,
    required this.profile,
    required this.entries,
    required this.schedules,
    required this.startupQuote,
    required this.rootDirectoryPath,
    required this.isWriteLocked,
    required this.onWriteBlocked,
    required this.onOpenSchedules,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
    required this.syncStatusRevision,
    required this.onShowSyncDetails,
    this.isSyncingOneDrive = false,
    this.isCancellingOneDriveSync = false,
    this.oneDriveSyncProgress,
    this.oneDriveSyncLabel,
    this.onTimelineBarVisibilityChanged,
    this.topContentInset = 0,
  });

  final CoupleProfile profile;
  final List<DiaryEntry> entries;
  final List<ScheduleItem> schedules;
  final String startupQuote;
  final String? rootDirectoryPath;
  final bool isWriteLocked;
  final VoidCallback onWriteBlocked;
  final ValueChanged<DateTime> onOpenSchedules;
  final ValueChanged<DiaryEntry> onOpenEntry;
  final Future<DiaryEntry?> Function(DiaryEntry entry) onEditEntry;
  final Future<void> Function(DiaryEntry entry) onDeleteEntry;
  final ValueListenable<int> syncStatusRevision;
  final VoidCallback onShowSyncDetails;
  final bool isSyncingOneDrive;
  final bool isCancellingOneDriveSync;
  final double? oneDriveSyncProgress;
  final String? oneDriveSyncLabel;
  final ValueChanged<bool>? onTimelineBarVisibilityChanged;
  final double topContentInset;

  @override
  State<RealHomeFlowPage> createState() => RealHomeFlowPageState();
}

class RealHomeFlowPageState extends State<RealHomeFlowPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _timelineKey = GlobalKey();
  bool _showTimelineBar = false;
  bool _timelineBarUpdateScheduled = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleTimelineBarUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateTimelineBar());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scheduleTimelineBarUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> scrollToTimeline() async {
    final timelineContext = _timelineKey.currentContext;
    if (timelineContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      timelineContext,
      duration: _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  void _scheduleTimelineBarUpdate() {
    if (_timelineBarUpdateScheduled) {
      return;
    }
    _timelineBarUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineBarUpdateScheduled = false;
      _updateTimelineBar();
    });
  }

  void _updateTimelineBar() {
    final timelineContext = _timelineKey.currentContext;
    if (timelineContext == null || !mounted) {
      return;
    }

    final box = timelineContext.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      return;
    }

    final topSafe = MediaQuery.paddingOf(context).top + 10;
    final timelineTop = box.localToGlobal(Offset.zero).dy;
    final shouldShow = timelineTop <= topSafe + 8;
    if (shouldShow == _showTimelineBar) {
      return;
    }

    setState(() {
      _showTimelineBar = shouldShow;
    });
    widget.onTimelineBarVisibilityChanged?.call(shouldShow);
  }

  void _openTimelineSearch() {
    showTimelineSearchPage(
      context: context,
      entries: widget.entries,
      rootDirectoryPath: widget.rootDirectoryPath,
      isWriteLocked: widget.isWriteLocked,
      onWriteBlocked: widget.onWriteBlocked,
      onOpenEntry: widget.onOpenEntry,
      onEditEntry: widget.onEditEntry,
      onDeleteEntry: widget.onDeleteEntry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final topPadding = mediaPadding.top + 14 + widget.topContentInset;
    final bottomPadding = mediaPadding.bottom + 104;

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(18, topPadding, 18, 0),
              sliver: SliverToBoxAdapter(
                child: TodayOverviewContent(
                  profile: widget.profile,
                  entries: widget.entries,
                  schedules: widget.schedules,
                  startupQuote: widget.startupQuote,
                  onOpenSchedules: widget.onOpenSchedules,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
            TimelineSliverSection(
              headerKey: _timelineKey,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              entries: widget.entries,
              rootDirectoryPath: widget.rootDirectoryPath,
              isWriteLocked: widget.isWriteLocked,
              onWriteBlocked: widget.onWriteBlocked,
              onOpenEntry: widget.onOpenEntry,
              onEditEntry: widget.onEditEntry,
              onDeleteEntry: widget.onDeleteEntry,
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
          ],
        ),
        _TimelineTopBar(
          visible: _showTimelineBar,
          reduceMotion: _reduceMotion,
          topInset: mediaPadding.top,
          isSyncing: widget.isSyncingOneDrive,
          isCancelling: widget.isCancellingOneDriveSync,
          progress: widget.oneDriveSyncProgress,
          syncLabel: widget.oneDriveSyncLabel,
          syncStatusRevision: widget.syncStatusRevision,
          onSearch: _openTimelineSearch,
          onShowSyncDetails: widget.onShowSyncDetails,
        ),
      ],
    );
  }
}

class _TimelineTopBar extends StatelessWidget {
  const _TimelineTopBar({
    required this.visible,
    required this.reduceMotion,
    required this.topInset,
    required this.isSyncing,
    required this.isCancelling,
    required this.progress,
    required this.syncLabel,
    required this.syncStatusRevision,
    required this.onSearch,
    required this.onShowSyncDetails,
  });

  final bool visible;
  final bool reduceMotion;
  final double topInset;
  final bool isSyncing;
  final bool isCancelling;
  final double? progress;
  final String? syncLabel;
  final ValueListenable<int> syncStatusRevision;
  final VoidCallback onSearch;
  final VoidCallback onShowSyncDetails;

  @override
  Widget build(BuildContext context) {
    final barHeight = topInset + 62;
    final child = IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: ValueListenableBuilder<int>(
          valueListenable: syncStatusRevision,
          builder: (context, _, _) {
            final effectiveProgress = progress?.clamp(0, 1).toDouble();
            final title = isSyncing ? (isCancelling ? '正在收尾' : '正在同步') : '时间轴';
            final subtitle = isSyncing
                ? (syncLabel?.trim().isNotEmpty == true
                      ? syncLabel!.trim()
                      : '正在把小日子放到云端')
                : null;

            return AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: barHeight,
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(22, topInset + 6, 14, 0),
              decoration: BoxDecoration(
                color: DiaryPalette.white.withValues(
                  alpha: isSyncing ? 0.92 : 0.86,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: DiaryPalette.line.withValues(alpha: 0.72),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: DiaryPalette.ink.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 160),
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                alignment: Alignment.centerLeft,
                                children: [...previousChildren, ?currentChild],
                              );
                            },
                            child: SizedBox(
                              key: ValueKey<String>('$title-${subtitle ?? ''}'),
                              width: double.infinity,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      title,
                                      textAlign: TextAlign.left,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: DiaryPalette.ink,
                                            fontWeight: FontWeight.w900,
                                            height: 1.05,
                                          ),
                                    ),
                                  ),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.left,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: DiaryPalette.wine,
                                            fontWeight: FontWeight.w700,
                                            height: 1.1,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: isSyncing ? '同步详情' : '搜索日记',
                          onPressed: isSyncing ? onShowSyncDetails : onSearch,
                          icon: Icon(
                            isSyncing
                                ? Icons.list_alt_rounded
                                : Icons.search_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: isSyncing ? 1 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      value: effectiveProgress,
                      backgroundColor: DiaryPalette.mist.withValues(
                        alpha: 0.65,
                      ),
                      color: isCancelling
                          ? DiaryPalette.wine
                          : DiaryPalette.rose,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    return Positioned(top: 0, left: 0, right: 0, child: child);
  }
}
