import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ui/diary_design.dart';

class GlassActionPill extends StatelessWidget {
  const GlassActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final radius = BorderRadius.circular(24);
    return RepaintBoundary(
      child: Tooltip(
        message: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              if (isEnabled) ...[
                BoxShadow(
                  color: DiaryPalette.rose.withValues(alpha: 0.20),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: DiaryPalette.white.withValues(alpha: 0.50),
                  blurRadius: 3,
                  offset: const Offset(0, -2),
                ),
              ],
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      DiaryPalette.white.withValues(
                        alpha: isEnabled ? 0.60 : 0.30,
                      ),
                      DiaryPalette.mist.withValues(
                        alpha: isEnabled ? 0.28 : 0.12,
                      ),
                    ],
                  ),
                  border: Border.all(
                    width: 1.4,
                    color: DiaryPalette.white.withValues(
                      alpha: isEnabled ? 0.85 : 0.50,
                    ),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: radius,
                    onTap: onPressed,
                    splashColor: DiaryPalette.rose.withValues(alpha: 0.12),
                    highlightColor: DiaryPalette.white.withValues(alpha: 0.10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
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
                                color: DiaryPalette.white.withValues(
                                  alpha: 0.70,
                                ),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              icon,
                              size: 18,
                              color: isEnabled
                                  ? DiaryPalette.rose
                                  : DiaryPalette.wine,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            label,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: isEnabled
                                      ? DiaryPalette.ink
                                      : DiaryPalette.wine,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassPlusButton extends StatelessWidget {
  const GlassPlusButton({super.key, required this.isOpen, required this.onPressed});

  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: DiaryPalette.rose.withValues(alpha: 0.20),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: DiaryPalette.white.withValues(alpha: 0.50),
              blurRadius: 3,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    DiaryPalette.white.withValues(alpha: 0.60),
                    DiaryPalette.mist.withValues(alpha: 0.28),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  width: 1.4,
                  color: DiaryPalette.white.withValues(alpha: 0.85),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPressed,
                  splashColor: DiaryPalette.rose.withValues(alpha: 0.10),
                  highlightColor: DiaryPalette.white.withValues(alpha: 0.12),
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      turns: isOpen ? 0.125 : 0,
                      child: const Icon(
                        Icons.add_rounded,
                        color: DiaryPalette.rose,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
