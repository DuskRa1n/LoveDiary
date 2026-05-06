part of '../../app.dart';

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _GlassActionPill extends StatelessWidget {
  const _GlassActionPill({
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
                  color: DiaryPalette.rose.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: DiaryPalette.white.withValues(alpha: 0.4),
                  blurRadius: 2,
                  offset: const Offset(0, -1),
                ),
              ],
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      DiaryPalette.white.withValues(
                        alpha: isEnabled ? 0.55 : 0.30,
                      ),
                      DiaryPalette.mist.withValues(
                        alpha: isEnabled ? 0.25 : 0.12,
                      ),
                    ],
                  ),
                  border: Border.all(
                    width: 1.2,
                    color: DiaryPalette.white.withValues(
                      alpha: isEnabled ? 0.80 : 0.50,
                    ),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        DiaryPalette.white.withValues(alpha: 0.30),
                        Colors.transparent,
                      ],
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
                                  color: DiaryPalette.white.withValues(alpha: 0.70),
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
      ),
    );
  }
}

class _GlassPlusButton extends StatelessWidget {
  const _GlassPlusButton({required this.isOpen, required this.onPressed});

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
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      DiaryPalette.white.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
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
                        child: Icon(
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
      ),
    );
  }
}

class _DeliberatePageScrollPhysics extends PageScrollPhysics {
  const _DeliberatePageScrollPhysics({super.parent});

  @override
  _DeliberatePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _DeliberatePageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 96;

  @override
  double get minFlingVelocity => 900;

  @override
  double? get dragStartDistanceMotionThreshold => 18;
}

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.currentIndex,
    required this.pageController,
    required this.onSelected,
  });

  final int currentIndex;
  final PageController pageController;
  final ValueChanged<int> onSelected;

  static const _items = [
    _FloatingTabSpec(
      label: '今天',
      icon: Icons.favorite_border_rounded,
      selectedIcon: Icons.favorite_rounded,
    ),
    _FloatingTabSpec(
      label: '回忆',
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories_rounded,
    ),
    _FloatingTabSpec(
      label: '我们',
      icon: Icons.people_alt_outlined,
      selectedIcon: Icons.people_alt_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: DiaryPalette.ink.withValues(alpha: 0.05),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: DiaryPalette.rose.withValues(alpha: 0.08),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: DiaryPalette.white.withValues(alpha: 0.40),
              blurRadius: 3,
              offset: const Offset(0, -2),
            ),
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
                    DiaryPalette.white.withValues(alpha: 0.55),
                    DiaryPalette.mist.withValues(alpha: 0.22),
                  ],
                ),
                border: Border.all(
                  width: 1.3,
                  color: DiaryPalette.white.withValues(alpha: 0.82),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      DiaryPalette.white.withValues(alpha: 0.28),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SizedBox(
                  height: 68,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const inset = 6.0;
                      final itemWidth =
                          (constraints.maxWidth - inset * 2) / _items.length;

                      return AnimatedBuilder(
                        animation: pageController,
                        builder: (context, _) {
                          final rawPage = pageController.hasClients
                              ? pageController.page ?? currentIndex.toDouble()
                              : currentIndex.toDouble();
                          final page = rawPage
                              .clamp(0.0, (_items.length - 1).toDouble())
                              .toDouble();

                          return Stack(
                            children: [
                              Positioned(
                                top: inset,
                                bottom: inset,
                                left: inset + itemWidth * page,
                                width: itemWidth,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        DiaryPalette.white.withValues(
                                          alpha: 0.70,
                                        ),
                                        DiaryPalette.mist.withValues(alpha: 0.52),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: DiaryPalette.white.withValues(
                                        alpha: 0.62,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(inset),
                                child: Row(
                                  children: [
                                    for (
                                      var index = 0;
                                      index < _items.length;
                                      index++
                                    )
                                      Expanded(
                                        child: _FloatingTabButton(
                                          spec: _items[index],
                                          selection: (1 - (page - index).abs())
                                              .clamp(0.0, 1.0)
                                              .toDouble(),
                                          selected: currentIndex == index,
                                          onTap: () => onSelected(index),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
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

class _FloatingTabSpec {
  const _FloatingTabSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _FloatingTabButton extends StatelessWidget {
  const _FloatingTabButton({
    required this.spec,
    required this.selection,
    required this.selected,
    required this.onTap,
  });

  final _FloatingTabSpec spec;
  final double selection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        Color.lerp(DiaryPalette.wine, DiaryPalette.rose, selection) ??
        DiaryPalette.wine;
    final weight = selection > 0.5 ? FontWeight.w900 : FontWeight.w700;
    return Semantics(
      selected: selected,
      button: true,
      label: spec.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            scale: 1 + selection * 0.035,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selection > 0.5 ? spec.selectedIcon : spec.icon,
                  color: foreground,
                  size: 22,
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  style:
                      Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: weight,
                      ) ??
                      TextStyle(color: foreground, fontWeight: weight),
                  child: Text(spec.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
