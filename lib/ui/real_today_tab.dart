import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import 'diary_design.dart';

class RealTodayTab extends StatelessWidget {
  const RealTodayTab({
    super.key,
    required this.profile,
    required this.entries,
    required this.rootDirectoryPath,
    required this.startupQuote,
    required this.onOpenEntry,
  });

  final CoupleProfile profile;
  final List<DiaryEntry> entries;
  final String? rootDirectoryPath;
  final String startupQuote;
  final ValueChanged<DiaryEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final recentEntries = entries.take(8).toList();
    final togetherDays =
        DateTime.now().difference(profile.togetherSince).inDays + 1;

    return DiaryPage(
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
          const DiarySectionHeader(
            title: '最近日记',
            subtitle: '横向浏览最近写下的日记，带图的像相册，无图的就专心读文字。',
          ),
          const SizedBox(height: 14),
          if (recentEntries.isEmpty)
            const DiaryEmptyState(
              title: '还没有最近记录',
              subtitle: '写下第一篇后，这里会变成你们的近期小相册。',
            )
          else
            SizedBox(
              height: 260,
              child: ListView.separated(
                clipBehavior: Clip.none,
                scrollDirection: Axis.horizontal,
                itemCount: recentEntries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final entry = recentEntries[index];
                  return _RecentMemoryCard(
                    entry: entry,
                    rootDirectoryPath: rootDirectoryPath,
                    onTap: () => onOpenEntry(entry),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

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

class _RecentMemoryCard extends StatelessWidget {
  const _RecentMemoryCard({
    required this.entry,
    required this.rootDirectoryPath,
    required this.onTap,
  });

  final DiaryEntry entry;
  final String? rootDirectoryPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = entry.attachments.isNotEmpty;

    return SizedBox(
      width: 190,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: DiaryPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImage) ...[
                DiaryCover(
                  rootDirectoryPath: rootDirectoryPath,
                  attachments: entry.attachments,
                  width: double.infinity,
                  height: 112,
                  radius: 22,
                ),
                const SizedBox(height: 12),
              ],
              Text(
                entry.title,
                maxLines: hasImage ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: DiaryPalette.ink,
                      fontWeight: FontWeight.w900,
                      height: 1.14,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '${formatDiaryShortDate(entry.createdAt)} ${formatDiaryTime(entry.createdAt)} · ${entry.mood}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: DiaryPalette.wine,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  entry.summary,
                  maxLines: hasImage ? 3 : 7,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DiaryPalette.wine,
                        height: 1.45,
                      ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (entry.attachments.isNotEmpty)
                    DiaryBadge(
                      label: '${entry.attachments.length} 图',
                      tone: DiaryBadgeTone.sand,
                    ),
                  if (entry.commentCount > 0)
                    DiaryBadge(
                      label: '${entry.commentCount} 评论',
                      tone: DiaryBadgeTone.ink,
                    ),
                  if (entry.attachments.isEmpty && entry.commentCount == 0)
                    DiaryBadge(label: entry.author, tone: DiaryBadgeTone.sand),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
