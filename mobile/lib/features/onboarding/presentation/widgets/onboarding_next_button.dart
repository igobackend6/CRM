import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The primary control under the slides.
///
/// On slides 1..n-1 it is a round arrow button wrapped in a ring that fills
/// as the user advances. On the last slide the ring fades away and the
/// circle stretches into a wide "Get Started" button.
class OnboardingNextButton extends StatelessWidget {
  const OnboardingNextButton({super.key, required this.progress, required this.isLast, required this.onPressed});

  /// 0..1 — how far through the slides the user is.
  final double progress;
  final bool isLast;
  final VoidCallback onPressed;

  static const double _ringSize = 92;
  static const double _circle = 68;
  static const double _wideWidth = 240;
  static const double _wideHeight = 60;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _wideWidth,
      height: _ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: isLast ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => CustomPaint(
                size: const Size(_ringSize, _ringSize),
                painter: _RingPainter(progress: value, track: scheme.outlineVariant, color: AppColors.accent),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeInOutCubic,
            width: isLast ? _wideWidth : _circle,
            height: isLast ? _wideHeight : _circle,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_circle / 2),
              gradient: const LinearGradient(colors: AppColors.gradientBrand, begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
              ],
            ),
            child: Semantics(
              button: true,
              label: isLast ? 'Get Started' : 'Next',
              excludeSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(_circle / 2),
                  onTap: onPressed,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: FittedBox(
                        key: ValueKey(isLast),
                        fit: BoxFit.scaleDown,
                        child: isLast
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Get Started',
                                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                                  ),
                                  SizedBox(width: 10),
                                  Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 22),
                                ],
                              )
                            : const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.color});

  final double progress;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.track != track || old.color != color;
}
