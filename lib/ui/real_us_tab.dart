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
    required this.onRunMaintenance,
    required this.onOpenDiagnostics,
    this.topContentInset = 0,
    this.sheetMode = false,
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
  final Future<void> Function() onRunMaintenance;
  final Future<void> Function() onOpenDiagnostics;
  final double topContentInset;
  final bool sheetMode;

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
      respectTopSafeArea: !sheetMode,
      padding: sheetMode
          ? const EdgeInsets.fromLTRB(18, 18, 18, 32)
          : EdgeInsets.fromLTRB(18, 14 + topContentInset, 18, 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DiaryReveal(
            child: _ProfileHeader(profile: profile, togetherDays: togetherDays),
          ),
          const SizedBox(height: 18),
          DiaryReveal(
            delay: const Duration(milliseconds: 110),
            offset: const Offset(0, 0.06),
            child: DiaryPanel(
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
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.health_and_safety_rounded,
                    title: '自检维护',
                    subtitle: '清理残留、重建索引、修复同步状态',
                    onTap: () {
                      onRunMaintenance();
                    },
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.tune_rounded,
                    title: '其他设置',
                    subtitle: '回收站、关于',
                    onTap: () => _openOtherSettings(
                      context,
                      commentCount: commentCount,
                      attachmentCount: attachmentCount,
                    ),
                  ),
                ],
              ),
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
              DiaryReveal(
                delay: const Duration(milliseconds: 190),
                scaleFrom: 0.96,
                offset: const Offset(0, 0.06),
                child: DiaryStatBlock(label: '日记', value: '${entries.length}'),
              ),
              DiaryReveal(
                delay: const Duration(milliseconds: 240),
                scaleFrom: 0.96,
                offset: const Offset(0, 0.06),
                child: DiaryStatBlock(
                  label: '评论',
                  value: '$commentCount',
                  accent: DiaryBadgeTone.ink,
                ),
              ),
              DiaryReveal(
                delay: const Duration(milliseconds: 290),
                scaleFrom: 0.96,
                offset: const Offset(0, 0.06),
                child: DiaryStatBlock(
                  label: '图片',
                  value: '$attachmentCount',
                  accent: DiaryBadgeTone.sand,
                ),
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
      return '最近失败：${formatDiaryDate(lastSyncFailedAt!)} ${formatDiaryTime(lastSyncFailedAt!)}';
    }
    if (lastSyncedAt == null) {
      return '尚未同步';
    }
    return '最近同步：${formatDiaryDate(lastSyncedAt!)} ${formatDiaryTime(lastSyncedAt!)}';
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
                          fontWeight: FontWeight.w800,
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
                        subtitle: '删除后的日记会先保留 7 天',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onOpenDustbin();
                        },
                      ),
                      const _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.bug_report_outlined,
                        title: '诊断日志',
                        subtitle: '查看最近的错误和后台任务记录',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onOpenDiagnostics();
                        },
                      ),
                      const _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        title: '关于此应用',
                        subtitle:
                            '${entries.length} 篇日记 · $commentCount 条评论 · $attachmentCount 张图片',
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
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: DiaryPalette.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: DiaryPalette.rose.withValues(alpha: 0.15),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFFBF5),
                        Color(0xFFFFE3DB),
                        Color(0xFFFFF0D8),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              DiaryPalette.mist.withValues(alpha: 0.96),
                              DiaryPalette.blush.withValues(alpha: 0.40),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: DiaryPalette.white,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: DiaryPalette.rose.withValues(alpha: 0.18),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: DiaryPalette.rose,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '恋爱日记',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: DiaryPalette.ink,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '版本 1.4.15+96',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DiaryPalette.wine.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '为两个人长期记录生活而设计的日记。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: DiaryPalette.wine,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 16,
                            color: DiaryPalette.wine.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '作者：Eric Chen',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: DiaryPalette.ink),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.cloud_sync_rounded,
                            size: 16,
                            color: DiaryPalette.wine.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '数据保存在本机，可选 OneDrive 同步到云端。同步过程中日记会暂时锁定，完成后自动恢复。',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: DiaryPalette.wine.withValues(
                                      alpha: 0.8,
                                    ),
                                    height: 1.5,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                            color: DiaryPalette.wine.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '删除的日记会进入回收站，7 天内可恢复。',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: DiaryPalette.wine.withValues(
                                      alpha: 0.8,
                                    ),
                                    height: 1.5,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      if (lastSyncFailureMessage != null &&
                          lastSyncFailureMessage!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: DiaryPalette.mist.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: DiaryPalette.blush.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: DiaryPalette.rose,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  lastSyncFailureMessage!.trim(),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: DiaryPalette.wine,
                                        height: 1.45,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          '愿你们把重要的小事，都认真留住。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: DiaryPalette.wine.withValues(alpha: 0.5),
                                fontStyle: FontStyle.italic,
                                height: 1.5,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: DiaryPalette.rose,
                        foregroundColor: DiaryPalette.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('知道了'),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    return DiaryAmbientFloat(
      duration: Duration(milliseconds: accent ? 4200 : 5100),
      dx: accent ? 0 : 2,
      dy: accent ? 4 : 6,
      child: Container(
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
            fontWeight: FontWeight.w800,
          ),
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
                      fontWeight: FontWeight.w800,
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      child: DiaryBadge(
        key: ValueKey<String>('$label-$active'),
        label: label,
        tone: active ? DiaryBadgeTone.rose : DiaryBadgeTone.ink,
      ),
    );
  }
}
