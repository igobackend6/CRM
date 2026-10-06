import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'mascot_state.dart';

/// Interactive Robot Mascot reacting live to login actions.
///
/// Features:
/// - Idle breathing bob and antenna sway
/// - Periodic arm waving and eye blinking
/// - Attentive smile when focusing on email/phone
/// - Privacy gesture (both hands cover eyes) when focusing on password
/// - Celebration bounce on login success
/// - Head shake with concerned expression on login failure
class RobotMascot extends StatefulWidget {
  const RobotMascot({
    super.key,
    required this.state,
    this.width = 160,
    this.height = 160,
    this.onErrorCompleted,
  });

  final MascotState state;
  final double width;
  final double height;
  final VoidCallback? onErrorCompleted;

  @override
  State<RobotMascot> createState() => _RobotMascotState();
}

class _RobotMascotState extends State<RobotMascot> with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _coverEyesController;
  late final AnimationController _errorShakeController;
  late final AnimationController _successBounceController;

  // Eye blink timer
  double _blinkValue = 0.0;
  DateTime _lastBlink = DateTime.now();

  @override
  void initState() {
    super.initState();

    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _coverEyesController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _errorShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onErrorCompleted?.call();
        }
      });

    _successBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _applyState(widget.state, isInit: true);
  }

  @override
  void didUpdateWidget(covariant RobotMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _applyState(widget.state);
    }
  }

  void _applyState(MascotState state, {bool isInit = false}) {
    switch (state) {
      case MascotState.passwordFocus:
        _coverEyesController.forward();
        _errorShakeController.reset();
        _successBounceController.reset();
        break;
      case MascotState.error:
        _coverEyesController.reverse();
        _errorShakeController.forward(from: 0.0);
        _successBounceController.reset();
        break;
      case MascotState.success:
        _coverEyesController.reverse();
        _errorShakeController.reset();
        _successBounceController.forward(from: 0.0);
        break;
      case MascotState.emailFocus:
      case MascotState.idle:
        _coverEyesController.reverse();
        _errorShakeController.reset();
        _successBounceController.reset();
        break;
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _coverEyesController.dispose();
    _errorShakeController.dispose();
    _successBounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _idleController,
        _coverEyesController,
        _errorShakeController,
        _successBounceController,
      ]),
      builder: (context, child) {
        final idleVal = _idleController.value;
        final coverProgress = CurvedAnimation(
          parent: _coverEyesController,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        ).value;

        // Head shake on error (damped sine wave)
        double headShakeOffset = 0.0;
        if (_errorShakeController.isAnimating) {
          final t = _errorShakeController.value;
          final decay = 1.0 - t;
          headShakeOffset = math.sin(t * math.pi * 8) * 12.0 * decay;
        }

        // Celebration bounce on success
        double bounceOffset = 0.0;
        if (_successBounceController.isAnimating) {
          final t = _successBounceController.value;
          bounceOffset = -math.sin(t * math.pi) * 14.0;
        }

        // Breathing float in idle/email
        final breathingOffset = math.sin(idleVal * 2 * math.pi) * 3.0;

        // Antenna sway
        final antennaAngle = math.sin(idleVal * 2 * math.pi) * 0.12;

        // Blink calculation
        final now = DateTime.now();
        if (widget.state != MascotState.passwordFocus &&
            now.difference(_lastBlink).inMilliseconds > 3600) {
          _lastBlink = now;
          _blinkValue = 1.0;
        } else if (_blinkValue > 0.0) {
          _blinkValue = math.max(0.0, _blinkValue - 0.15);
        }

        // Arm wave when idle (wave between 0.3 and 0.7 of idle cycle)
        double waveAngle = 0.0;
        if (widget.state == MascotState.idle && idleVal > 0.35 && idleVal < 0.75) {
          final waveCycle = (idleVal - 0.35) / 0.40;
          waveAngle = math.sin(waveCycle * math.pi * 4) * 0.32;
        }

        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: CustomPaint(
            painter: _RobotPainter(
              state: widget.state,
              coverProgress: coverProgress,
              headShakeX: headShakeOffset,
              bounceY: bounceOffset,
              breathingY: breathingOffset,
              antennaAngle: antennaAngle,
              waveAngle: waveAngle,
              blinkValue: _blinkValue,
            ),
          ),
        );
      },
    );
  }
}

class _RobotPainter extends CustomPainter {
  _RobotPainter({
    required this.state,
    required this.coverProgress,
    required this.headShakeX,
    required this.bounceY,
    required this.breathingY,
    required this.antennaAngle,
    required this.waveAngle,
    required this.blinkValue,
  });

  final MascotState state;
  final double coverProgress; // 0.0 (open) to 1.0 (covering eyes)
  final double headShakeX;
  final double bounceY;
  final double breathingY;
  final double antennaAngle;
  final double waveAngle;
  final double blinkValue;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 160.0;
    canvas.save();
    canvas.scale(scale, scale);

    final centerX = 80.0;
    final totalYOffset = breathingY + bounceY;

    // 1. Shadow underneath the robot
    final shadowPaint = Paint()
      ..color = const Color(0x221D4ED8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(80, 148),
        width: 86 - bounceY * 0.5,
        height: 14 - bounceY * 0.2,
      ),
      shadowPaint,
    );

    // 2. Torso (Body)
    final bodyCenterY = 118.0 + totalYOffset;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, bodyCenterY), width: 72, height: 46),
      const Radius.circular(16),
    );

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
      ).createShader(bodyRect.outerRect);
    canvas.drawRRect(bodyRect, bodyPaint);

    final bodyStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFF94A3B8);
    canvas.drawRRect(bodyRect, bodyStroke);

    // Chest badge / power LED
    final badgePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      ).createShader(Rect.fromCircle(center: Offset(centerX, bodyCenterY - 2), radius: 8));
    canvas.drawCircle(Offset(centerX, bodyCenterY - 2), 6.5, badgePaint);

    final badgeInner = Paint()..color = const Color(0xFF93C5FD);
    canvas.drawCircle(Offset(centerX, bodyCenterY - 2), 2.5, badgeInner);

    // 3. Head & Face (affected by headShakeX)
    final headCenterX = centerX + headShakeX;
    final headCenterY = 68.0 + totalYOffset;

    // --- Antenna ---
    canvas.save();
    canvas.translate(headCenterX, headCenterY - 32);
    canvas.rotate(antennaAngle);

    final antennaStem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF64748B);
    canvas.drawLine(Offset.zero, const Offset(0, -18), antennaStem);

    // Glowing tip
    final glowPaint = Paint()
      ..color = (state == MascotState.error)
          ? const Color(0x66EF4444)
          : (state == MascotState.success)
              ? const Color(0x6610B981)
              : const Color(0x6638BDF8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(const Offset(0, -20), 8, glowPaint);

    final tipPaint = Paint()
      ..color = (state == MascotState.error)
          ? const Color(0xFFEF4444)
          : (state == MascotState.success)
              ? const Color(0xFF10B981)
              : const Color(0xFF38BDF8);
    canvas.drawCircle(const Offset(0, -20), 5.5, tipPaint);
    canvas.restore();

    // --- Head Shell ---
    final headRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(headCenterX, headCenterY), width: 90, height: 64),
      const Radius.circular(22),
    );

    // Ear bolts
    final earPaint = Paint()..color = const Color(0xFF94A3B8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(headCenterX - 46, headCenterY), width: 6, height: 22),
        const Radius.circular(3),
      ),
      earPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(headCenterX + 46, headCenterY), width: 6, height: 22),
        const Radius.circular(3),
      ),
      earPaint,
    );

    final headPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF1F5F9), Color(0xFFCBD5E1)],
      ).createShader(headRect.outerRect);
    canvas.drawRRect(headRect, headPaint);

    final headStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFF94A3B8);
    canvas.drawRRect(headRect, headStroke);

    // --- Face Visor (Gloss Screen) ---
    final visorRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(headCenterX, headCenterY + 1), width: 72, height: 44),
      const Radius.circular(15),
    );

    final visorPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRRect(visorRect, visorPaint);

    // Visor subtle glass shine
    final shinePath = Path()
      ..moveTo(headCenterX - 30, headCenterY - 18)
      ..lineTo(headCenterX + 10, headCenterY - 18)
      ..lineTo(headCenterX - 10, headCenterY + 18)
      ..lineTo(headCenterX - 30, headCenterY + 18)
      ..close();
    final shinePaint = Paint()
      ..color = const Color(0x15FFFFFF)
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.clipRRect(visorRect);
    canvas.drawPath(shinePath, shinePaint);
    canvas.restore();

    // --- Eyes ---
    final eyeY = headCenterY - 3;
    final leftEyeX = headCenterX - 16;
    final rightEyeX = headCenterX + 16;

    final eyeColor = (state == MascotState.error)
        ? const Color(0xFFF87171)
        : (state == MascotState.success)
            ? const Color(0xFF34D399)
            : const Color(0xFF38BDF8);

    final eyePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.fill;

    // If covering eyes with hands or password focus: narrow eyes
    final eyeScaleY = (state == MascotState.passwordFocus || coverProgress > 0.0)
        ? (0.35 + 0.65 * (1.0 - coverProgress))
        : (1.0 - blinkValue * 0.9);

    if (state == MascotState.success) {
      // Happy curved eyes: ^ ^
      final happyEye = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = eyeColor;

      canvas.drawArc(
        Rect.fromCenter(center: Offset(leftEyeX, eyeY), width: 14, height: 12),
        math.pi * 1.1,
        math.pi * 0.8,
        false,
        happyEye,
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(rightEyeX, eyeY), width: 14, height: 12),
        math.pi * 1.1,
        math.pi * 0.8,
        false,
        happyEye,
      );
    } else if (state == MascotState.error) {
      // Concerned angled eyes
      final errorEye = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..color = eyeColor;

      // > < shape or sloped bars
      canvas.drawLine(
        Offset(leftEyeX - 6, eyeY - 4),
        Offset(leftEyeX + 6, eyeY + 4),
        errorEye,
      );
      canvas.drawLine(
        Offset(leftEyeX - 6, eyeY + 4),
        Offset(leftEyeX + 6, eyeY - 4),
        errorEye,
      );

      canvas.drawLine(
        Offset(rightEyeX - 6, eyeY - 4),
        Offset(rightEyeX + 6, eyeY + 4),
        errorEye,
      );
      canvas.drawLine(
        Offset(rightEyeX - 6, eyeY + 4),
        Offset(rightEyeX + 6, eyeY - 4),
        errorEye,
      );
    } else {
      // Normal friendly oval / capsule eyes
      canvas.save();
      canvas.translate(leftEyeX, eyeY);
      canvas.scale(1.0, eyeScaleY);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 12, height: 16),
          const Radius.circular(6),
        ),
        eyePaint,
      );
      // Small eye specular highlight
      if (eyeScaleY > 0.6) {
        canvas.drawCircle(const Offset(-2, -3), 2.0, Paint()..color = Colors.white);
      }
      canvas.restore();

      canvas.save();
      canvas.translate(rightEyeX, eyeY);
      canvas.scale(1.0, eyeScaleY);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 12, height: 16),
          const Radius.circular(6),
        ),
        eyePaint,
      );
      if (eyeScaleY > 0.6) {
        canvas.drawCircle(const Offset(-2, -3), 2.0, Paint()..color = Colors.white);
      }
      canvas.restore();
    }

    // --- Mouth ---
    final mouthY = headCenterY + 12;
    final mouthPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = eyeColor;

    if (state == MascotState.success) {
      // Big open happy smile
      canvas.drawArc(
        Rect.fromCenter(center: Offset(headCenterX, mouthY - 2), width: 18, height: 12),
        0.1,
        math.pi * 0.8,
        false,
        mouthPaint,
      );
    } else if (state == MascotState.emailFocus) {
      // Cheerful smile
      canvas.drawArc(
        Rect.fromCenter(center: Offset(headCenterX, mouthY - 1), width: 14, height: 8),
        0.2,
        math.pi * 0.7,
        false,
        mouthPaint,
      );
    } else if (state == MascotState.passwordFocus || coverProgress > 0.5) {
      // Cute small 'o' mouth (shy peek)
      canvas.drawCircle(Offset(headCenterX, mouthY), 3.0, mouthPaint);
    } else if (state == MascotState.error) {
      // Downturned concerned mouth
      canvas.drawArc(
        Rect.fromCenter(center: Offset(headCenterX, mouthY + 3), width: 14, height: 8),
        math.pi * 1.2,
        math.pi * 0.6,
        false,
        mouthPaint,
      );
    } else {
      // Neutral gentle friendly curve
      canvas.drawLine(
        Offset(headCenterX - 5, mouthY),
        Offset(headCenterX + 5, mouthY),
        mouthPaint,
      );
    }

    // 4. Arms & Hands
    // Privacy Gesture: When coverProgress -> 1.0, both arms move up and hands cover the eyes!
    _drawArms(
      canvas: canvas,
      centerX: centerX,
      headCenterX: headCenterX,
      headCenterY: headCenterY,
      bodyCenterY: bodyCenterY,
      coverProgress: coverProgress,
      waveAngle: waveAngle,
      isSuccess: state == MascotState.success,
    );

    canvas.restore();
  }

  void _drawArms({
    required Canvas canvas,
    required double centerX,
    required double headCenterX,
    required double headCenterY,
    required double bodyCenterY,
    required double coverProgress,
    required double waveAngle,
    required bool isSuccess,
  }) {
    final armColor = const Color(0xFFCBD5E1);
    final armStroke = const Color(0xFF94A3B8);

    final armPaint = Paint()
      ..color = armColor
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = armStroke;

    // Shoulder anchor points
    final leftShoulder = Offset(centerX - 36, bodyCenterY - 10);
    final rightShoulder = Offset(centerX + 36, bodyCenterY - 10);

    // --- Left Hand Target ---
    // At rest: resting by hip
    final leftRestHand = Offset(centerX - 42, bodyCenterY + 12);
    // Covering eye: covers left eye area
    final leftCoverHand = Offset(headCenterX - 16, headCenterY - 2);
    // Success: raised hand
    final leftSuccessHand = Offset(centerX - 46, headCenterY - 18);

    final leftTargetHand = isSuccess
        ? leftSuccessHand
        : Offset.lerp(leftRestHand, leftCoverHand, coverProgress)!;

    // Draw Left Arm
    _drawMechanicalArm(
      canvas: canvas,
      shoulder: leftShoulder,
      hand: leftTargetHand,
      isLeft: true,
      armPaint: armPaint,
      strokePaint: strokePaint,
      coverProgress: coverProgress,
    );

    // --- Right Hand Target ---
    final rightRestHand = Offset(centerX + 42, bodyCenterY + 12);
    final rightCoverHand = Offset(headCenterX + 16, headCenterY - 2);
    final rightSuccessHand = Offset(centerX + 46, headCenterY - 18);

    Offset rightTargetHand;
    if (isSuccess) {
      rightTargetHand = rightSuccessHand;
    } else if (coverProgress > 0.0) {
      rightTargetHand = Offset.lerp(rightRestHand, rightCoverHand, coverProgress)!;
    } else {
      // Apply waving angle
      final wavedX = rightRestHand.dx + math.sin(waveAngle) * 8;
      final wavedY = rightRestHand.dy - math.cos(waveAngle) * 14 + 14;
      rightTargetHand = Offset(wavedX, wavedY);
    }

    // Draw Right Arm
    _drawMechanicalArm(
      canvas: canvas,
      shoulder: rightShoulder,
      hand: rightTargetHand,
      isLeft: false,
      armPaint: armPaint,
      strokePaint: strokePaint,
      coverProgress: coverProgress,
    );
  }

  void _drawMechanicalArm({
    required Canvas canvas,
    required Offset shoulder,
    required Offset hand,
    required bool isLeft,
    required Paint armPaint,
    required Paint strokePaint,
    required double coverProgress,
  }) {
    // Shoulder joint
    canvas.drawCircle(shoulder, 6.0, armPaint);
    canvas.drawCircle(shoulder, 6.0, strokePaint);

    // Arm segment path (curved / segmented)
    final midElbowX = isLeft
        ? math.min(shoulder.dx, hand.dx) - (coverProgress > 0.1 ? 14 : 6)
        : math.max(shoulder.dx, hand.dx) + (coverProgress > 0.1 ? 14 : 6);
    final midElbowY = (shoulder.dy + hand.dy) / 2 + (coverProgress > 0.1 ? 6 : 2);

    final elbow = Offset(midElbowX, midElbowY);

    // Upper arm
    final armPath = Path()
      ..moveTo(shoulder.dx, shoulder.dy)
      ..quadraticBezierTo(elbow.dx, elbow.dy, hand.dx, hand.dy);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFCBD5E1);
    canvas.drawPath(armPath, linePaint);

    final lineStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF94A3B8);
    canvas.drawPath(armPath, lineStroke);

    // Hand mitten
    final handRadius = 10.0 + coverProgress * 3.0; // Grows slightly as it covers eyes
    canvas.drawCircle(hand, handRadius, armPaint);
    canvas.drawCircle(hand, handRadius, strokePaint);

    // Robot fingers detail
    final fingerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF94A3B8);
    canvas.drawLine(
      Offset(hand.dx - 4, hand.dy - 3),
      Offset(hand.dx + 4, hand.dy - 3),
      fingerPaint,
    );
    canvas.drawLine(
      Offset(hand.dx - 4, hand.dy + 2),
      Offset(hand.dx + 4, hand.dy + 2),
      fingerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RobotPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.coverProgress != coverProgress ||
        oldDelegate.headShakeX != headShakeX ||
        oldDelegate.bounceY != bounceY ||
        oldDelegate.breathingY != breathingY ||
        oldDelegate.antennaAngle != antennaAngle ||
        oldDelegate.waveAngle != waveAngle ||
        oldDelegate.blinkValue != blinkValue;
  }
}
