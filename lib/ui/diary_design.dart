import 'dart:io';

import 'package:flutter/material.dart';

import '../models/diary_models.dart';

class DiaryPalette {
  static const paper = Color(0xFFF6F0E8);
  static const shell = Color(0xFFFFFCF8);
  static const blush = Color(0xFFE7B9C5);
  static const rose = Color(0xFFC96A84);
  static const wine = Color(0xFF6D4353);
  static const ink = Color(0xFF2E2327);
  static const sand = Color(0xFFE8D6BF);
  static const line = Color(0xFFE9DDD1);
  static const mist = Color(0xFFF4E8ED);
  static const white = Colors.white;
}

class DiaryPage extends StatelessWidget {
  const DiaryPage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 112),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          left: -56,
          top: -10,
          child: _BackdropBlob(
            size: 164,
            color: Color(0xFFF0D6DF),
          ),
        ),
        const Positioned(
          right: -42,
          top: 118,
          child: _BackdropBlob(
            size: 132,
            color: Color(0xFFECDDC9),
          ),
        ),
        const Positioned(
          right: 24,
          bottom: 88,
          child: _BackdropBlob(
            size: 92,
            color: Color(0xFFF6E7ED),
          ),
        ),
        ListView(
          padding: padding,
          children: [child],
        ),
      ],
    );
  }
}

class DiaryHero extends StatelessWidget {
  const DiaryHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.footer,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DiaryPalette.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: DiaryPalette.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A5D3946),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: DiaryPalette.rose,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: DiaryPalette.ink,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: DiaryPalette.wine,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 16),
                trailing!,
              ],
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 20),
            footer!,
          ],
        ],
      ),
    );
  }
}

class DiaryPanel extends StatelessWidget {
  const DiaryPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: DiaryPalette.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: DiaryPalette.line),
      ),
      child: child,
    );
  }
}

class DiarySectionHeader extends StatelessWidget {
  const DiarySectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: DiaryPalette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: DiaryPalette.wine,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 12),
          action!,
        ],
      ],
    );
  }
}

class DiaryBadge extends StatelessWidget {
  const DiaryBadge({
    super.key,
    required this.label,
    this.tone = DiaryBadgeTone.rose,
  });

  final String label;
  final DiaryBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      DiaryBadgeTone.rose => (DiaryPalette.mist, DiaryPalette.rose),
      DiaryBadgeTone.sand => (const Color(0xFFF5EDDF), const Color(0xFF9B6C3E)),
      DiaryBadgeTone.ink => (const Color(0xFFF0EBE6), DiaryPalette.wine),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum DiaryBadgeTone { rose, sand, ink }

class DiaryEmptyState extends StatelessWidget {
  const DiaryEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.auto_stories_outlined,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DiaryPanel(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: DiaryPalette.mist,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: DiaryPalette.rose, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: DiaryPalette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: DiaryPalette.wine,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class DiaryCover extends StatelessWidget {
  const DiaryCover({
    super.key,
    required this.rootDirectoryPath,
    required this.attachments,
    this.width,
    this.height,
    this.radius = 22,
    this.iconSize = 26,
  });

  final String? rootDirectoryPath;
  final List<DiaryAttachment> attachments;
  final double? width;
  final double? height;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final attachment = attachments.isEmpty ? null : attachments.first;
    if (attachment == null) {
      return _DiaryCoverPlaceholder(
        count: 0,
        width: width,
        height: height,
        radius: radius,
        iconSize: iconSize,
      );
    }

    final file = File(resolveStoredPath(rootDirectoryPath, attachment.path));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        file,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _DiaryCoverPlaceholder(
          count: attachments.length,
          width: width,
          height: height,
          radius: radius,
          iconSize: iconSize,
        ),
      ),
    );
  }
}

class _DiaryCoverPlaceholder extends StatelessWidget {
  const _DiaryCoverPlaceholder({
    required this.count,
    required this.width,
    required this.height,
    required this.radius,
    required this.iconSize,
  });

  final int count;
  final double? width;
  final double? height;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: DiaryPalette.mist,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_outlined, size: iconSize, color: DiaryPalette.rose),
          if (count > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$count 张图',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: DiaryPalette.rose,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DiaryStatBlock extends StatelessWidget {
  const DiaryStatBlock({
    super.key,
    required this.label,
    required this.value,
    this.accent = DiaryBadgeTone.rose,
  });

  final String label;
  final String value;
  final DiaryBadgeTone accent;

  @override
  Widget build(BuildContext context) {
    final color = switch (accent) {
      DiaryBadgeTone.rose => DiaryPalette.rose,
      DiaryBadgeTone.sand => const Color(0xFF9B6C3E),
      DiaryBadgeTone.ink => DiaryPalette.wine,
    };

    return DiaryPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: DiaryPalette.wine,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class DiaryActionRow extends StatelessWidget {
  const DiaryActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: DiaryPalette.mist,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: DiaryPalette.rose),
            ),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DiaryPalette.wine,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: DiaryPalette.wine),
          ],
        ),
      ),
    );
  }
}

class _BackdropBlob extends StatelessWidget {
  const _BackdropBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

String resolveStoredPath(String? rootDirectoryPath, String storedPath) {
  final normalized = storedPath.replaceAll('\\', '/');
  final isAbsoluteUnix = normalized.startsWith('/');
  final isAbsoluteWindows = RegExp(r'^[a-zA-Z]:/').hasMatch(normalized);
  if (isAbsoluteUnix || isAbsoluteWindows || rootDirectoryPath == null) {
    return storedPath;
  }

  final normalizedRoot = rootDirectoryPath.replaceAll('\\', '/');
  return '$normalizedRoot/$normalized';
}

String formatDiaryDate(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日';
}

String formatDiaryShortDate(DateTime date) {
  return '${date.month}/${date.day}';
}

String formatDiaryTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

bool isSameDiaryDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
