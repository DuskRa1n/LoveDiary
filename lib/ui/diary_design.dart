import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/diary_models.dart';

class DiaryPalette {
  static const paper = Color(0xFFFFF1E8);
  static const shell = Color(0xFFFFFBF5);
  static const blush = Color(0xFFF7B3A8);
  static const rose = Color(0xFFD97862);
  static const wine = Color(0xFF785348);
  static const ink = Color(0xFF251917);
  static const sand = Color(0xFFF2D9B6);
  static const line = Color(0xFFEFD9CC);
  static const mist = Color(0xFFFFE4DF);
  static const tea = Color(0xFFB87C50);
  static const white = Colors.white;
}

class DiaryPage extends StatelessWidget {
  const DiaryPage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 22, 18, 112),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _DiaryBackground()),
        ListView(padding: padding, children: [child]),
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
    this.quote,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;
  final String? quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: DiaryPalette.rose.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFFFBF5),
                    const Color(0xFFFFE3DB),
                    const Color(0xFFFFF0D8),
                  ],
                ),
                border: Border.all(
                  color: DiaryPalette.white.withValues(alpha: 0.74),
                ),
              ),
            ),
          ),
          const Positioned(
            right: -62,
            top: -52,
            child: _SoftOrb(size: 176, color: Color(0xFFFFC8C0)),
          ),
          const Positioned(
            left: -54,
            bottom: -82,
            child: _SoftOrb(size: 180, color: Color(0xFFF4D6A9)),
          ),
          Positioned.fill(child: CustomPaint(painter: _HeroLinePainter())),
          Padding(
            padding: const EdgeInsets.all(24),
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
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: DiaryPalette.ink,
                              fontWeight: FontWeight.w900,
                              height: 1.04,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Text(
                              subtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: DiaryPalette.wine,
                                height: 1.65,
                              ),
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
                if (footer != null) ...[const SizedBox(height: 22), footer!],
                if (quote != null && quote!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: DiaryPalette.white.withValues(alpha: 0.46),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: DiaryPalette.white.withValues(alpha: 0.72),
                      ),
                    ),
                    child: Text(
                      quote!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: DiaryPalette.wine,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
        color: DiaryPalette.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: DiaryPalette.white.withValues(alpha: 0.78)),
        boxShadow: [
          BoxShadow(
            color: DiaryPalette.rose.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
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
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 3,
                    decoration: BoxDecoration(
                      color: DiaryPalette.rose,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: DiaryPalette.ink,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
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
    final (background, foreground, border) = switch (tone) {
      DiaryBadgeTone.rose => (
        const Color(0xFFFFE8E4),
        DiaryPalette.rose,
        const Color(0xFFF1C2B9),
      ),
      DiaryBadgeTone.sand => (
        const Color(0xFFFFF0DA),
        DiaryPalette.tea,
        const Color(0xFFE9C89D),
      ),
      DiaryBadgeTone.ink => (
        const Color(0xFFF3E8E2),
        DiaryPalette.wine,
        const Color(0xFFE2CBC0),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          height: 1.1,
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE5DF), Color(0xFFFFF2D9)],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: DiaryPalette.white),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: DiaryPalette.rose, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: DiaryPalette.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: DiaryPalette.wine,
              height: 1.55,
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

    final path = attachment.thumbnailOrFallbackPath;
    if (path.isEmpty) {
      return _DiaryCoverPlaceholder(
        count: attachments.length,
        width: width,
        height: height,
        radius: radius,
        iconSize: iconSize,
      );
    }

    final file = File(resolveStoredPath(rootDirectoryPath, path));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: DiaryPalette.ink.withValues(alpha: 0.13),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          file,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _DiaryCoverPlaceholder(
            count: attachments.length,
            width: width,
            height: height,
            radius: radius,
            iconSize: iconSize,
          ),
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE6E1), Color(0xFFFFF1DD)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: DiaryPalette.white),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: iconSize, color: DiaryPalette.rose),
          if (count > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$count 张图片',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: DiaryPalette.rose,
                fontWeight: FontWeight.w800,
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
      DiaryBadgeTone.sand => DiaryPalette.tea,
      DiaryBadgeTone.ink => DiaryPalette.wine,
    };

    return DiaryPanel(
      padding: const EdgeInsets.all(18),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -20,
            child: _SoftOrb(size: 58, color: color.withValues(alpha: 0.20)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: DiaryPalette.wine,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: DiaryPalette.mist,
                shape: BoxShape.circle,
                border: Border.all(color: DiaryPalette.white),
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
                      fontWeight: FontWeight.w900,
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

class _DiaryBackground extends StatelessWidget {
  const _DiaryBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFEFE9), Color(0xFFFFF7E8), Color(0xFFFFE8E4)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _PaperPainter())),
          const Positioned(
            left: -72,
            top: -40,
            child: _SoftOrb(size: 190, color: Color(0xFFFFC8C0)),
          ),
          const Positioned(
            right: -64,
            top: 132,
            child: _SoftOrb(size: 148, color: Color(0xFFFFE0B9)),
          ),
          const Positioned(
            right: 26,
            bottom: 76,
            child: _SoftOrb(size: 102, color: Color(0xFFFFD9D8)),
          ),
          const Positioned(
            left: 28,
            top: 96,
            child: _FloatingHeart(size: 18, opacity: 0.42),
          ),
          const Positioned(right: 42, top: 70, child: _CloudPuff()),
          const Positioned(left: -14, bottom: 72, child: _FlowerSilhouette()),
        ],
      ),
    );
  }
}

class _FloatingHeart extends StatelessWidget {
  const _FloatingHeart({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Icon(
        Icons.favorite_rounded,
        size: size,
        color: DiaryPalette.rose.withValues(alpha: opacity),
      ),
    );
  }
}

class _CloudPuff extends StatelessWidget {
  const _CloudPuff();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 82,
        height: 40,
        child: Stack(
          children: [
            Positioned(left: 8, bottom: 4, child: _CloudCircle(size: 34)),
            const Positioned(
              left: 28,
              bottom: 12,
              child: _CloudCircle(size: 42),
            ),
            const Positioned(
              right: 6,
              bottom: 3,
              child: _CloudCircle(size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudCircle extends StatelessWidget {
  const _CloudCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _FlowerSilhouette extends StatelessWidget {
  const _FlowerSilhouette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.18,
        child: SizedBox(
          width: 94,
          height: 130,
          child: CustomPaint(painter: _FlowerPainter()),
        ),
      ),
    );
  }
}

class _SoftOrb extends StatelessWidget {
  const _SoftOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.62),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = DiaryPalette.line.withValues(alpha: 0.24)
      ..strokeWidth = 1;
    for (var y = 88.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final dotPaint = Paint()
      ..color = DiaryPalette.rose.withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 56; i++) {
      final x = (i * 47) % math.max(size.width, 1);
      final y = 26 + ((i * 83) % math.max(size.height, 1));
      canvas.drawCircle(Offset(x.toDouble(), y.toDouble()), 1.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlowerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stemPaint = Paint()
      ..color = DiaryPalette.tea
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final flowerPaint = Paint()
      ..color = DiaryPalette.rose
      ..style = PaintingStyle.fill;

    final stem = Path()
      ..moveTo(size.width * 0.46, size.height)
      ..quadraticBezierTo(
        size.width * 0.30,
        size.height * 0.58,
        size.width * 0.54,
        size.height * 0.20,
      );
    canvas.drawPath(stem, stemPaint);

    for (final offset in [
      Offset(size.width * 0.42, size.height * 0.28),
      Offset(size.width * 0.58, size.height * 0.25),
      Offset(size.width * 0.49, size.height * 0.13),
      Offset(size.width * 0.35, size.height * 0.18),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: offset, width: 36, height: 28),
        flowerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeroLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = DiaryPalette.rose.withValues(alpha: 0.16)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.56, 0)
      ..quadraticBezierTo(
        size.width * 0.48,
        size.height * 0.46,
        size.width * 0.56,
        size.height,
      );
    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..color = DiaryPalette.tea.withValues(alpha: 0.25)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 18; i++) {
      canvas.drawCircle(
        Offset(size.width * 0.68 + i * 7, size.height * 0.36 + math.sin(i) * 4),
        1.4,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
