import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import '../sync/onedrive/onedrive_models.dart';
import 'diary_design.dart';

class RealUsTab extends StatelessWidget {
  const RealUsTab({
    super.key,
    required this.profile,
    required this.entries,
    required this.oneDriveConfig,
    required this.lastSyncedAt,
    required this.lastSyncFailedAt,
    required this.lastSyncFailureMessage,
    required this.onEditProfile,
    required this.onOpenDustbin,
    required this.onConnectOneDrive,
    required this.onOpenOneDriveSettings,
    this.topContentInset = 0,
  });

  final CoupleProfile profile;
  final List<DiaryEntry> entries;
  final OneDriveSyncConfig? oneDriveConfig;
  final DateTime? lastSyncedAt;
  final DateTime? lastSyncFailedAt;
  final String? lastSyncFailureMessage;
  final VoidCallback onEditProfile;
  final Future<void> Function() onOpenDustbin;
  final Future<void> Function() onConnectOneDrive;
  final Future<void> Function() onOpenOneDriveSettings;
  final double topContentInset;

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
      showBackground: false,
      respectTopSafeArea: true,
      padding: EdgeInsets.fromLTRB(18, 14 + topContentInset, 18, 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileHeader(profile: profile, togetherDays: togetherDays),
          const SizedBox(height: 18),
          DiaryPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.favorite_rounded,
                  title: '关系信息',
                  onTap: onEditProfile,
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.cloud_sync_rounded,
                  title: 'OneDrive 同步',
                  subtitle: _oneDriveSubtitle(),
                  trailing: _StatusPill(
                    label: oneDriveConfig == null ? '未连接' : '已连接',
                    active: oneDriveConfig != null,
                  ),
                  onTap: oneDriveConfig == null
                      ? () => onConnectOneDrive()
                      : onOpenOneDriveSettings,
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.tune_rounded,
                  title: '其他设置',
                  onTap: () => _openOtherSettings(
                    context,
                    commentCount: commentCount,
                    attachmentCount: attachmentCount,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
            children: [
              DiaryStatBlock(label: '日记', value: '${entries.length}'),
              DiaryStatBlock(
                label: '评论',
                value: '$commentCount',
                accent: DiaryBadgeTone.ink,
              ),
              DiaryStatBlock(
                label: '图片',
                value: '$attachmentCount',
                accent: DiaryBadgeTone.sand,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _oneDriveSubtitle() {
    if (oneDriveConfig == null) {
      return '主同步通道';
    }
    if (lastSyncFailedAt != null &&
        (lastSyncedAt == null || lastSyncFailedAt!.isAfter(lastSyncedAt!))) {
      final failedText =
          '${formatDiaryDate(lastSyncFailedAt!)} ${formatDiaryTime(lastSyncFailedAt!)}';
      final message = lastSyncFailureMessage;
      if (message != null && message.isNotEmpty) {
        return '最近失败：$failedText';
      }
      return '最近失败：$failedText';
    }
    final syncedText = lastSyncedAt == null
        ? '尚未同步'
        : '${formatDiaryDate(lastSyncedAt!)} ${formatDiaryTime(lastSyncedAt!)}';
    return '最近同步：$syncedText';
  }

  void _openOtherSettings(
    BuildContext context, {
    required int commentCount,
    required int attachmentCount,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '其他设置',
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(
                          color: DiaryPalette.ink,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                DiaryPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.restore_from_trash_rounded,
                        title: '回收站',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onOpenDustbin();
                        },
                      ),
                      const _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        title: '关于此应用',
                        subtitle:
                            '${entries.length} 篇日记 · $commentCount 条评论 · $attachmentCount 张图',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _showAbout(context);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('关于恋爱日记'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('两个人私用的恋爱日记。'),
              SizedBox(height: 14),
              Text('作者：Eric Chen'),
              SizedBox(height: 8),
              Text('版本：1.2.12+66'),
              SizedBox(height: 14),
              Text('数据优先保存在本机，同步只用于你主动连接的云端。'),
              SizedBox(height: 8),
              Text('OneDrive 是当前唯一同步方式。'),
              SizedBox(height: 14),
              Text('愿这些普通日子，都被好好留下。'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.togetherDays});

  final CoupleProfile profile;
  final int togetherDays;

  @override
  Widget build(BuildContext context) {
    return DiaryHero(
      eyebrow: '我们',
      title: profile.currentUserName,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AvatarBubble(label: profile.currentUserName, accent: true),
          Transform.translate(
            offset: const Offset(-10, 0),
            child: _AvatarBubble(label: profile.partnerName),
          ),
        ],
      ),
      footer: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          DiaryBadge(label: '已连接 ${profile.partnerName}'),
          DiaryBadge(label: '在一起 $togetherDays 天', tone: DiaryBadgeTone.sand),
          DiaryBadge(
            label: '纪念日 ${formatDiaryShortDate(profile.togetherSince)}',
            tone: DiaryBadgeTone.ink,
          ),
        ],
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim().characters.first;
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: accent ? DiaryPalette.mist : const Color(0xFFFFF4E8),
        shape: BoxShape.circle,
        border: Border.all(color: DiaryPalette.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: DiaryPalette.rose.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: accent ? DiaryPalette.rose : DiaryPalette.tea,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: DiaryPalette.mist,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: DiaryPalette.rose, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: DiaryPalette.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DiaryPalette.wine,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  color: DiaryPalette.wine,
                ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 52,
      color: DiaryPalette.line.withValues(alpha: 0.72),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DiaryBadge(
      label: label,
      tone: active ? DiaryBadgeTone.rose : DiaryBadgeTone.ink,
    );
  }
}
