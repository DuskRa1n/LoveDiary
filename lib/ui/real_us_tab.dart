import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import '../sync/webdav/webdav_models.dart';
import 'diary_design.dart';

class RealUsTab extends StatelessWidget {
  const RealUsTab({
    super.key,
    required this.profile,
    required this.entries,
    required this.jianguoyunConfig,
    required this.lastSyncedAt,
    required this.isEditingJianguoyun,
    required this.isSyncingJianguoyun,
    required this.onEditProfile,
    required this.onOpenDustbin,
    required this.onOpenJianguoyunSettings,
    required this.onSyncJianguoyun,
    required this.onDisconnectJianguoyun,
  });

  final CoupleProfile profile;
  final List<DiaryEntry> entries;
  final WebDavSyncConfig? jianguoyunConfig;
  final DateTime? lastSyncedAt;
  final bool isEditingJianguoyun;
  final bool isSyncingJianguoyun;
  final VoidCallback onEditProfile;
  final Future<void> Function() onOpenDustbin;
  final Future<void> Function() onOpenJianguoyunSettings;
  final Future<void> Function() onSyncJianguoyun;
  final Future<void> Function() onDisconnectJianguoyun;

  @override
  Widget build(BuildContext context) {
    final commentCount = entries.fold<int>(
      0,
      (total, entry) => total + entry.commentCount,
    );
    final attachmentCount = entries.fold<int>(
      0,
      (total, entry) => total + entry.attachments.length,
    );
    final togetherDays =
        DateTime.now().difference(profile.togetherSince).inDays + 1;

    return DiaryPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DiaryHero(
            eyebrow: '我们',
            title: '${profile.maleName} 和 ${profile.femaleName}',
            subtitle: '这里放的是你们的资料、同步状态和一些累计统计。日常不常改，但每次回来看都很有分量。',
            footer: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                DiaryBadge(label: '在一起 $togetherDays 天'),
                DiaryBadge(
                  label: '纪念日 ${formatDiaryShortDate(profile.togetherSince)}',
                  tone: DiaryBadgeTone.sand,
                ),
                DiaryBadge(
                  label: '他 · ${profile.maleName}',
                  tone: DiaryBadgeTone.ink,
                ),
                DiaryBadge(
                  label: '她 · ${profile.femaleName}',
                  tone: DiaryBadgeTone.ink,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const DiarySectionHeader(
            title: '资料与回收站',
            subtitle: '常用的资料维护和误删恢复入口都放在这里。',
          ),
          const SizedBox(height: 14),
          DiaryPanel(
            child: Column(
              children: [
                DiaryActionRow(
                  icon: Icons.edit_rounded,
                  title: '编辑我们',
                  subtitle: '修改名字、在一起日期和展示信息。',
                  onTap: onEditProfile,
                ),
                const Divider(height: 20, color: DiaryPalette.line),
                DiaryActionRow(
                  icon: Icons.restore_from_trash_rounded,
                  title: '回收站',
                  subtitle: '删除后的日记会先放这里，7 天后才会真正清理。',
                  onTap: onOpenDustbin,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const DiarySectionHeader(
            title: '坚果云同步',
            subtitle: '这里管理连接状态、同步操作和远端目录信息。',
          ),
          const SizedBox(height: 14),
          DiaryPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DiaryBadge(
                      label: jianguoyunConfig == null ? '未连接' : '已连接',
                    ),
                    if (jianguoyunConfig != null)
                      DiaryBadge(
                        label: jianguoyunConfig!.username,
                        tone: DiaryBadgeTone.ink,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  lastSyncedAt == null
                      ? '最近同步：尚未同步'
                      : '最近同步：${formatDiaryDate(lastSyncedAt!)} ${formatDiaryTime(lastSyncedAt!)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: DiaryPalette.wine,
                  ),
                ),
                if (jianguoyunConfig != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '远端目录：${jianguoyunConfig!.remoteFolder}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DiaryPalette.wine,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: isEditingJianguoyun || isSyncingJianguoyun
                          ? null
                          : (jianguoyunConfig == null
                                ? onOpenJianguoyunSettings
                                : onSyncJianguoyun),
                      icon: Icon(
                        jianguoyunConfig == null
                            ? Icons.settings_rounded
                            : Icons.sync_rounded,
                      ),
                      label: Text(
                        jianguoyunConfig == null
                            ? (isEditingJianguoyun ? '配置中...' : '配置坚果云')
                            : (isSyncingJianguoyun ? '同步中...' : '立即同步'),
                      ),
                    ),
                    if (jianguoyunConfig != null)
                      OutlinedButton.icon(
                        onPressed: isEditingJianguoyun || isSyncingJianguoyun
                            ? null
                            : onOpenJianguoyunSettings,
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('修改配置'),
                      ),
                    if (jianguoyunConfig != null)
                      OutlinedButton.icon(
                        onPressed: isEditingJianguoyun || isSyncingJianguoyun
                            ? null
                            : onDisconnectJianguoyun,
                        icon: const Icon(Icons.link_off_rounded),
                        label: const Text('断开连接'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const DiarySectionHeader(
            title: '统计',
            subtitle: '你们已经写下的日记、评论和图片都会在这里累计显示。',
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.28,
            children: [
              DiaryStatBlock(label: '日记', value: '${entries.length} 篇'),
              DiaryStatBlock(
                label: '评论',
                value: '$commentCount 条',
                accent: DiaryBadgeTone.ink,
              ),
              DiaryStatBlock(
                label: '图片',
                value: '$attachmentCount 张',
                accent: DiaryBadgeTone.sand,
              ),
              DiaryStatBlock(
                label: '最近心情',
                value: entries.isEmpty ? '--' : entries.first.mood,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
