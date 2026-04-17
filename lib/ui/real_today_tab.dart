import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import 'diary_design.dart';

class RealTodayTab extends StatelessWidget {
  const RealTodayTab({
    super.key,
    required this.profile,
    required this.entries,
    required this.rootDirectoryPath,
    required this.onOpenEntry,
  });

  final CoupleProfile profile;
  final List<DiaryEntry> entries;
  final String? rootDirectoryPath;
  final ValueChanged<DiaryEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final latestEntries = entries.take(3).toList();
    final togetherDays =
        DateTime.now().difference(profile.togetherSince).inDays + 1;

    return DiaryPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DiaryHero(
            eyebrow: '首页',
            title: '${profile.currentUserName}和${profile.partnerName}',
            subtitle: '把今天值得记住的小事留在这里。日子不一定轰轰烈烈，但回头看时，会发现每一篇都很重要。',
            trailing: Container(
              width: 78,
              height: 78,
              decoration: const BoxDecoration(
                color: DiaryPalette.mist,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$togetherDays',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: DiaryPalette.rose,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
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
          const SizedBox(height: 24),
          const DiarySectionHeader(
            title: '最近日记',
            subtitle: '按创建时间倒序显示。',
          ),
          const SizedBox(height: 14),
          if (latestEntries.isEmpty)
            const DiaryEmptyState(
              title: '还没有日记',
              subtitle: '先写第一篇，再回来这里看最近记录。',
            )
          else
            ...latestEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _TodayEntryCard(
                  entry: entry,
                  rootDirectoryPath: rootDirectoryPath,
                  onTap: () => onOpenEntry(entry),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayEntryCard extends StatelessWidget {
  const _TodayEntryCard({
    required this.entry,
    required this.rootDirectoryPath,
    required this.onTap,
  });

  final DiaryEntry entry;
  final String? rootDirectoryPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: DiaryPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DiaryCover(
              rootDirectoryPath: rootDirectoryPath,
              attachments: entry.attachments,
              width: 104,
              height: 132,
              radius: 24,
              iconSize: 30,
            ),
            const SizedBox(width: 16),
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
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.summary,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                            '${formatDiaryDate(entry.createdAt)} ${formatDiaryTime(entry.createdAt)}',
                        tone: DiaryBadgeTone.ink,
                      ),
                      if (entry.updatedAt != null)
                        DiaryBadge(
                          label:
                              '更新 ${formatDiaryShortDate(entry.updatedAt!)} ${formatDiaryTime(entry.updatedAt!)}',
                          tone: DiaryBadgeTone.sand,
                        ),
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
                    ],
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
