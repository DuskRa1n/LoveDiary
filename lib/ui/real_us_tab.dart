import 'package:flutter/material.dart';

import '../models/diary_models.dart';
import '../sync/onedrive/onedrive_models.dart';
import '../sync/webdav/webdav_models.dart';
import 'diary_design.dart';

class RealUsTab extends StatelessWidget {
  const RealUsTab({
    super.key,
    required this.profile,
    required this.entries,
    required this.oneDriveConfig,
    required this.jianguoyunConfig,
    required this.lastSyncedAt,
    required this.isSyncingOneDrive,
    required this.oneDriveSyncProgress,
    required this.oneDriveSyncLabel,
    required this.isEditingJianguoyun,
    required this.isSyncingJianguoyun,
    required this.onEditProfile,
    required this.onOpenDustbin,
    required this.onConnectOneDrive,
    required this.onOpenOneDriveSettings,
    required this.onOpenJianguoyunSettings,
    required this.onSyncJianguoyun,
    required this.onDisconnectJianguoyun,
  });

  final CoupleProfile profile;
  final List<DiaryEntry> entries;
  final OneDriveSyncConfig? oneDriveConfig;
  final WebDavSyncConfig? jianguoyunConfig;
  final DateTime? lastSyncedAt;
  final bool isSyncingOneDrive;
  final double? oneDriveSyncProgress;
  final String? oneDriveSyncLabel;
  final bool isEditingJianguoyun;
  final bool isSyncingJianguoyun;
  final VoidCallback onEditProfile;
  final Future<void> Function() onOpenDustbin;
  final Future<void> Function() onConnectOneDrive;
  final Future<void> Function() onOpenOneDriveSettings;
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
          _ProfileHeader(profile: profile, togetherDays: togetherDays),
          const SizedBox(height: 18),
          DiaryPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.favorite_rounded,
                  title: '关系信息',
                  subtitle: '名字、纪念日、主视角',
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
                if (isSyncingOneDrive) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: oneDriveSyncProgress),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      oneDriveSyncLabel ?? '正在把今天的记忆放回云端...',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: DiaryPalette.wine),
                    ),
                  ),
                ],
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.tune_rounded,
                  title: '其他设置',
                  subtitle: '备用同步、回收站、关于',
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
                        icon: Icons.backup_rounded,
                        title: '备用同步',
                        subtitle: jianguoyunConfig == null
                            ? '坚果云未配置'
                            : '坚果云：${jianguoyunConfig!.remoteFolder}',
                        trailing: _StatusPill(
                          label: jianguoyunConfig == null ? '备用' : '已配置',
                          active: jianguoyunConfig != null,
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onOpenJianguoyunSettings();
                        },
                      ),
                      if (jianguoyunConfig != null) ...[
                        const SizedBox(height: 10),
                        _InlineSyncActions(
                          isBusy: isEditingJianguoyun || isSyncingJianguoyun,
                          primaryLabel: isSyncingJianguoyun ? '同步中...' : '立即同步',
                          secondaryLabel: '断开连接',
                          onPrimary: onSyncJianguoyun,
                          onSecondary: onDisconnectJianguoyun,
                        ),
                      ],
                      const _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.restore_from_trash_rounded,
                        title: '回收站',
                        subtitle: '删除后保留 7 天',
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
              Text('版本：0.7.3+32'),
              SizedBox(height: 14),
              Text('数据优先保存在本机，同步只用于你主动连接的云端。'),
              SizedBox(height: 8),
              Text('OneDrive 是主要同步方式，坚果云保留为备用方案。'),
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
      subtitle: '个人信息设置',
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
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DiaryPalette.wine,
                      height: 1.35,
                    ),
                  ),
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

class _InlineSyncActions extends StatelessWidget {
  const _InlineSyncActions({
    required this.isBusy,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
  });

  final bool isBusy;
  final String primaryLabel;
  final String secondaryLabel;
  final Future<void> Function() onPrimary;
  final Future<void> Function() onSecondary;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: isBusy ? null : onPrimary,
            icon: const Icon(Icons.sync_rounded),
            label: Text(primaryLabel),
          ),
          OutlinedButton.icon(
            onPressed: isBusy ? null : onSecondary,
            icon: const Icon(Icons.link_off_rounded),
            label: Text(secondaryLabel),
          ),
        ],
      ),
    );
  }
}
