import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'mascot_state.dart';
import 'robot_mascot.dart';

/// Animated Winter Scene holding the [RobotMascot].
///
/// Features:
/// - Layered sky gradient with soft radial glow
/// - Drifting fluffy clouds
/// - Jagged pale mountain silhouettes
/// - Layered winter pine trees with snow tips
/// - Rounded snow mounds and banks
/// - Gently falling and swaying snow particles
/// - Clean hero caption banner: "Every lead, every call. One clear pipeline."
class RobotScene extends StatefulWidget {
  const RobotScene({
    super.key,
    required this.state,
    this.height = 240,
    this.showCaption = true,
    this.onErrorCompleted,
  });

  final MascotState state;
  final double height;
  final bool showCaption;
  final VoidCallback? onErrorCompleted;

  @override
  State<RobotScene> createState() => _RobotSceneState();
}

class _RobotSceneState extends State<RobotScene> with SingleTickerProviderStateMixin {
  late final AnimationController _sceneController;
  final List<_SnowParticle> _particles = [];
  final math.Random _random = math.Random(42);

  @override
  void initState() {
    super.initState();
    _sceneController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();

    // Initialize snow particles
    for (int i = 0; i < 16; i++) {
      _particles.add(
        _SnowParticle(
          xFraction: _random.nextDouble(),
          yFraction: _random.nextDouble(),
          radius: 1.5 + _random.nextDouble() * 2.2,
          speed: 0.15 + _random.nextDouble() * 0.35,
          driftSpeed: 1.0 + _random.nextDouble() * 2.0,
          driftAmplitude: 8.0 + _random.nextDouble() * 12.0,
          opacity: 0.4 + _random.nextDouble() * 0.5,
        ),
      );
    }
  }

  @override
  void dispose() {
    _sceneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final totalHeight = widget.height + topPadding;

    return Container(
      height: totalHeight,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE7F3FC),
            Color(0xFFCCE7F9),
            Color(0xFFAFDBF5),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Scene background (mountains, clouds, trees, snow, falling snow particles)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _sceneController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _WinterScenePainter(
                    animationValue: _sceneController.value,
                    particles: _particles,
                  ),
                );
              },
            ),
          ),

          // 2. Interactive Robot Mascot
          Positioned(
            bottom: 8,
            child: RobotMascot(
              state: widget.state,
              width: 165,
              height: 165,
              onErrorCompleted: widget.onErrorCompleted,
            ),
          ),

          // 3. Hero Caption Overlay
          if (widget.showCaption)
            Positioned(
              top: topPadding + 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x660F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 13, color: Color(0xFF93C5FD)),
                    SizedBox(width: 4),
                    Text(
                      'EVERY LEAD, EVERY CALL • ONE CLEAR PIPELINE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SnowParticle {
  _SnowParticle({
    required this.xFraction,
    required this.yFraction,
    required this.radius,
    required this.speed,
    required this.driftSpeed,
    required this.driftAmplitude,
    required this.opacity,
  });

  final double xFraction;
  final double yFraction;
  final double radius;
  final double speed;
  final double driftSpeed;
  final double driftAmplitude;
  final double opacity;
}

class _WinterScenePainter extends CustomPainter {
  _WinterScenePainter({
    required this.animationValue,
    required this.particles,
  });

  final double animationValue;
  final List<_SnowParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    // A. Soft radial glow at top
    final radialGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.8),
        radius: 0.9,
        colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), radialGlow);

    // B. Mountains (jagged peaks in background)
    _drawMountains(canvas, size);

    // C. Drifting clouds
    _drawClouds(canvas, size, animationValue);

    // D. Back trees
    _drawPineTrees(
      canvas: canvas,
      size: size,
      treeColor: const Color(0xFF7BA3C8),
      snowColor: const Color(0xFFDCEAF7),
      heightMultiplier: 0.65,
      yBase: size.height - 24,
      isBackRow: true,
    );

    // E. Front trees
    _drawPineTrees(
      canvas: canvas,
      size: size,
      treeColor: const Color(0xFF2B5B7D),
      snowColor: const Color(0xFFFFFFFF),
      heightMultiplier: 1.0,
      yBase: size.height - 10,
      isBackRow: false,
    );

    // F. Snow Ground Mounds
    _drawSnowGround(canvas, size);

    // G. Snow particles
    _drawSnowParticles(canvas, size, animationValue);
  }

  void _drawMountains(Canvas canvas, Size size) {
    final mountainPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFC0DBF4), Color(0xFFD4E7F8)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..moveTo(-20, size.height - 25)
      ..lineTo(size.width * 0.15, size.height * 0.45)
      ..lineTo(size.width * 0.32, size.height * 0.68)
      ..lineTo(size.width * 0.52, size.height * 0.38)
      ..lineTo(size.width * 0.70, size.height * 0.65)
      ..lineTo(size.width * 0.88, size.height * 0.42)
      ..lineTo(size.width + 20, size.height - 25)
      ..lineTo(size.width + 20, size.height)
      ..lineTo(-20, size.height)
      ..close();

    canvas.drawPath(path, mountainPaint);
  }

  void _drawClouds(Canvas canvas, Size size, double progress) {
    final cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85);

    // Cloud 1
    final c1X = (size.width * 0.15 + progress * size.width * 0.7) % (size.width + 80) - 40;
    _drawCloudShape(canvas, Offset(c1X, size.height * 0.22), 24, cloudPaint);

    // Cloud 2 (moving faster)
    final c2X = (size.width * 0.65 + progress * size.width * 1.1) % (size.width + 90) - 45;
    _drawCloudShape(canvas, Offset(c2X, size.height * 0.32), 20, cloudPaint);

    // Cloud 3
    final c3X = (size.width * 0.85 + progress * size.width * 0.5) % (size.width + 70) - 35;
    _drawCloudShape(canvas, Offset(c3X, size.height * 0.16), 18, cloudPaint);
  }

  void _drawCloudShape(Canvas canvas, Offset center, double size, Paint paint) {
    canvas.drawCircle(center, size * 0.75, paint);
    canvas.drawCircle(Offset(center.dx - size * 0.7, center.dy + size * 0.2), size * 0.55, paint);
    canvas.drawCircle(Offset(center.dx + size * 0.7, center.dy + size * 0.2), size * 0.6, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy + size * 0.35),
          width: size * 2.2,
          height: size * 0.6,
        ),
        Radius.circular(size * 0.3),
      ),
      paint,
    );
  }

  void _drawPineTrees({
    required Canvas canvas,
    required Size size,
    required Color treeColor,
    required Color snowColor,
    required double heightMultiplier,
    required double yBase,
    required bool isBackRow,
  }) {
    final treePaint = Paint()..color = treeColor;
    final snowPaint = Paint()..color = snowColor;

    // We place 2 trees on the left, 2 trees on the right
    final positions = isBackRow
        ? [size.width * 0.08, size.width * 0.22, size.width * 0.76, size.width * 0.90]
        : [size.width * 0.04, size.width * 0.16, size.width * 0.82, size.width * 0.94];

    for (int i = 0; i < positions.length; i++) {
      final x = positions[i];
      final treeHeight = (38.0 + (i % 2 == 0 ? 8 : 0)) * heightMultiplier;
      final treeWidth = (22.0 + (i % 2 == 0 ? 4 : 0)) * heightMultiplier;

      // 3 tiered pine tree
      _drawPineTier(canvas, Offset(x, yBase - treeHeight * 0.4), treeWidth * 1.0, treeHeight * 0.45, treePaint, snowPaint);
      _drawPineTier(canvas, Offset(x, yBase - treeHeight * 0.7), treeWidth * 0.8, treeHeight * 0.40, treePaint, snowPaint);
      _drawPineTier(canvas, Offset(x, yBase - treeHeight * 0.95), treeWidth * 0.6, treeHeight * 0.35, treePaint, snowPaint);
    }
  }

  void _drawPineTier(Canvas canvas, Offset center, double width, double height, Paint treePaint, Paint snowPaint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - height / 2)
      ..lineTo(center.dx - width / 2, center.dy + height / 2)
      ..lineTo(center.dx + width / 2, center.dy + height / 2)
      ..close();
    canvas.drawPath(path, treePaint);

    // Snow cap on tier top
    final snowCap = Path()
      ..moveTo(center.dx, center.dy - height / 2)
      ..lineTo(center.dx - width * 0.25, center.dy)
      ..lineTo(center.dx + width * 0.25, center.dy)
      ..close();
    canvas.drawPath(snowCap, snowPaint);
  }

  void _drawSnowGround(Canvas canvas, Size size) {
    final groundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE2EFFB), Color(0xFFFFFFFF)],
      ).createShader(Rect.fromLTWH(0, size.height - 40, size.width, 40));

    final path = Path()
      ..moveTo(0, size.height - 24)
      ..quadraticBezierTo(size.width * 0.25, size.height - 34, size.width * 0.5, size.height - 22)
      ..quadraticBezierTo(size.width * 0.78, size.height - 12, size.width, size.height - 26)
      ..lineTo(size.width, size.height + 2)
      ..lineTo(0, size.height + 2)
      ..close();

    canvas.drawPath(path, groundPaint);

    // Solid white base to seamlessly merge with the form background
    final baseFill = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 6, size.width, 8), baseFill);

    // Top gentle highlight ridge
    final ridgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x66FFFFFF);

    final ridgePath = Path()
      ..moveTo(0, size.height - 24)
      ..quadraticBezierTo(size.width * 0.25, size.height - 34, size.width * 0.5, size.height - 22)
      ..quadraticBezierTo(size.width * 0.78, size.height - 12, size.width, size.height - 26);

    canvas.drawPath(ridgePath, ridgePaint);
  }

  void _drawSnowParticles(Canvas canvas, Size size, double progress) {
    for (final p in particles) {
      // Calculate continuous falling y
      final yProgress = (p.yFraction + progress * p.speed * 8.0) % 1.0;
      final y = yProgress * size.height;

      // Gentle horizontal sway
      final sway = math.sin((progress * p.driftSpeed * 2 * math.pi) + p.xFraction * 10) * p.driftAmplitude;
      final x = (p.xFraction * size.width + sway) % size.width;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: p.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WinterScenePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
