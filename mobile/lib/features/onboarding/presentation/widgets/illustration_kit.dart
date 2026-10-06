import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Maps [t] (0..1) onto the sub-range [start]..[end], eased by [curve].
/// Lets one 0..1 "intro" value drive many staggered animations.
double segment(double t, double start, double end, [Curve curve = Curves.easeOutCubic]) {
  if (end <= start) return t >= end ? 1 : 0;
  return curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
}

typedef IllustrationBuilder = Widget Function(BuildContext context, double intro, double loop);

/// Drives one slide's illustration with two clocks:
///  * `intro` (0→1, once) replays every time the slide becomes [active];
///  * `loop` (0→1, repeating) is the gentle ambient motion while it is.
///
/// Honors the OS "remove animations" setting: the finished illustration
/// is shown static, with no ticking at all.
class AnimatedIllustration extends StatefulWidget {
  const AnimatedIllustration({
    super.key,
    required this.active,
    required this.builder,
    this.loopDuration = const Duration(seconds: 5),
  });

  final bool active;
  final IllustrationBuilder builder;
  final Duration loopDuration;

  @override
  State<AnimatedIllustration> createState() => _AnimatedIllustrationState();
}

class _AnimatedIllustrationState extends State<AnimatedIllustration> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  late final AnimationController _loop = AnimationController(vsync: this, duration: widget.loopDuration);
  Timer? _resetTimer;
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      widget.active ? _activate() : _deactivate();
    }
  }

  @override
  void didUpdateWidget(AnimatedIllustration old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _activate();
    if (!widget.active && old.active) _deactivate();
  }

  void _activate() {
    _resetTimer?.cancel();
    if (_reduceMotion) {
      _intro.value = 1;
      _loop
        ..stop()
        ..value = 0.5;
      return;
    }
    _intro.forward(from: 0);
    _loop.repeat();
  }

  void _deactivate() {
    _loop.stop();
    if (_reduceMotion) {
      _intro.value = 1;
      return;
    }
    // Keep the finished frame while the slide is still partly on screen
    // during the swipe, then rewind so it replays on the next visit.
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !widget.active) _intro.value = 0;
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _loop]),
      builder: (context, _) => widget.builder(context, _intro.value, _loop.value),
    );
  }
}

/// A fixed 300×300 drawing surface, scaled to fit whatever space the slide
/// gives it — so every illustration is laid out in plain coordinates.
class IllustrationStage extends StatelessWidget {
  const IllustrationStage({super.key, required this.children});

  static const double size = 300;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: _BackdropPainter(Theme.of(context)))),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.theme);

  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = theme.brightness == Brightness.dark;
    final center = size.center(Offset.zero);
    final radius = size.width * 0.47;

    canvas.drawCircle(center, radius, Paint()..color = dark ? AppColors.accentBgDark : AppColors.accentBg);

    // Faint blueprint grid, clipped to the disc.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
    final line = Paint()
      ..color = (dark ? Colors.white : AppColors.accent).withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (double p = 0; p <= size.width; p += 30) {
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), line);
      canvas.drawLine(Offset(0, p), Offset(size.width, p), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.theme.brightness != theme.brightness;
}

/// White (or dark-surface) rounded card used inside the illustrations.
BoxDecoration illustrationCard(BuildContext context, {double radius = 14}) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 5)),
    ],
  );
}

/// Grey placeholder line standing in for text, like a wireframe.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, required this.width, this.height = 6});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(height),
      ),
    );
  }
}

/// Dashed circle outline.
void drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint, {double dash = 6, double gap = 6}) {
  final metric = (Path()..addOval(Rect.fromCircle(center: center, radius: radius))).computeMetrics().first;
  for (double d = 0; d < metric.length; d += dash + gap) {
    canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
  }
}
