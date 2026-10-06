import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/onboarding_page_data.dart';
import 'illustration_kit.dart';

/// Picks the animated illustration for a slide.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({super.key, required this.type, required this.active});

  final OnboardingIllustrationType type;
  final bool active;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case OnboardingIllustrationType.hub:
        return HubIllustration(active: active);
      case OnboardingIllustrationType.analytics:
        return AnalyticsIllustration(active: active);
      case OnboardingIllustrationType.timeline:
        return TimelineIllustration(active: active);
      case OnboardingIllustrationType.followUps:
        return FollowUpsIllustration(active: active);
      case OnboardingIllustrationType.team:
        return TeamIllustration(active: active);
    }
  }
}

// ---------------------------------------------------------------------------
// 1. Hub — leads, calls, follow-ups and analytics orbiting one CRM core.
// ---------------------------------------------------------------------------

class HubIllustration extends StatelessWidget {
  const HubIllustration({super.key, required this.active});

  final bool active;

  static const _orbiters = [
    (Icons.people_alt_rounded, AppColors.accent, 'Leads'),
    (Icons.call_rounded, AppColors.success, 'Calls'),
    (Icons.event_available_rounded, AppColors.violet, 'Follow-ups'),
    (Icons.insights_rounded, AppColors.gold, 'Analytics'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedIllustration(
      active: active,
      loopDuration: const Duration(seconds: 16),
      builder: (context, intro, loop) {
        const center = Offset(150, 150);
        const orbit = 104.0;
        final spin = loop * 2 * math.pi;

        final positions = [
          for (var i = 0; i < _orbiters.length; i++)
            center +
                Offset(
                  math.cos(-math.pi / 2 + i * math.pi / 2 + spin),
                  math.sin(-math.pi / 2 + i * math.pi / 2 + spin),
                ) *
                    orbit,
        ];

        return IllustrationStage(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _HubPainter(
                  center: center,
                  orbit: orbit,
                  positions: positions,
                  reveal: segment(intro, 0, 0.5),
                  loop: loop,
                  color: AppColors.accent,
                ),
              ),
            ),
            for (var i = 0; i < _orbiters.length; i++)
              Positioned(
                left: positions[i].dx - 40,
                top: positions[i].dy - 26,
                width: 80,
                child: Transform.scale(
                  scale: segment(intro, 0.25 + i * 0.1, 0.75 + i * 0.1, Curves.elasticOut),
                  child: _OrbiterBubble(icon: _orbiters[i].$1, color: _orbiters[i].$2, label: _orbiters[i].$3),
                ),
              ),
            Positioned(
              left: center.dx - 44,
              top: center.dy - 44,
              child: Transform.scale(
                scale: segment(intro, 0, 0.45, Curves.easeOutBack),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: AppColors.gradientBrand,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: const Icon(Icons.hub_rounded, color: Colors.white, size: 42),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OrbiterBubble extends StatelessWidget {
  const _OrbiterBubble({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surface,
            border: Border.all(color: color, width: 1.6),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _HubPainter extends CustomPainter {
  _HubPainter({
    required this.center,
    required this.orbit,
    required this.positions,
    required this.reveal,
    required this.loop,
    required this.color,
  });

  final Offset center;
  final double orbit;
  final List<Offset> positions;
  final double reveal;
  final double loop;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Dashed orbit ring.
    drawDashedCircle(
      canvas,
      center,
      orbit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.35 * reveal),
    );

    // Spokes from the core to each orbiter.
    final spoke = Paint()
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.25 * reveal);
    for (final p in positions) {
      canvas.drawLine(center, Offset.lerp(center, p, reveal)!, spoke);
    }

    // Two soft pulses radiating from the core.
    for (final shift in [0.0, 0.5]) {
      final p = (loop * 3 + shift) % 1;
      canvas.drawCircle(
        center,
        44 + 44 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.28 * (1 - p) * reveal),
      );
    }
  }

  @override
  bool shouldRepaint(_HubPainter old) => true;
}

// ---------------------------------------------------------------------------
// 2. Analytics — bars grow, a trend line draws over them, rings fill.
// ---------------------------------------------------------------------------

class AnalyticsIllustration extends StatelessWidget {
  const AnalyticsIllustration({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedIllustration(
      active: active,
      builder: (context, intro, loop) {
        final bob = math.sin(loop * 2 * math.pi) * 4;
        return IllustrationStage(
          children: [
            Positioned(
              left: 38,
              top: 96,
              width: 224,
              height: 150,
              child: Opacity(
                opacity: segment(intro, 0, 0.25),
                child: Container(
                  decoration: illustrationCard(context),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Calls this week',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurface),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.trending_up_rounded,
                            size: 16,
                            color: AppColors.success.withValues(alpha: segment(intro, 0.6, 1)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _BarsPainter(
                            intro: intro,
                            loop: loop,
                            lineColor: AppColors.success,
                            dotRing: scheme.surface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 30,
              top: 24,
              child: _DonutCard(value: 0.6, color: AppColors.accent, progress: segment(intro, 0.3, 0.9), label: '60%'),
            ),
            Positioned(
              left: 206,
              top: 16,
              child: _DonutCard(value: 0.75, color: AppColors.gold, progress: segment(intro, 0.4, 1), label: '75%'),
            ),
            Positioned(
              left: 216,
              top: 214 + bob,
              child: Transform.scale(
                scale: segment(intro, 0.5, 0.9, Curves.elasticOut),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: AppColors.gradientBrand,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: const Icon(Icons.call_rounded, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DonutCard extends StatelessWidget {
  const _DonutCard({required this.value, required this.color, required this.progress, required this.label});

  final double value;
  final Color color;
  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      decoration: illustrationCard(context, radius: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(46, 46),
            painter: _DonutPainter(
              value: value * progress,
              color: color,
              track: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          Opacity(
            opacity: progress,
            child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, stroke..color = color);
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.value != value || old.color != color || old.track != track;
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.intro, required this.loop, required this.lineColor, required this.dotRing});

  final double intro;
  final double loop;
  final Color lineColor;
  final Color dotRing;

  static const _values = [0.36, 0.55, 0.42, 0.7, 0.5, 0.86, 0.66];

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 8.0;
    final n = _values.length;
    final barW = (size.width - gap * (n - 1)) / n;
    final tops = <Offset>[];

    for (var i = 0; i < n; i++) {
      final h = size.height * _values[i] * segment(intro, 0.1 + i * 0.07, 0.55 + i * 0.07);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (barW + gap), size.height - h, barW, h),
        const Radius.circular(4),
      );
      final best = i == 5;
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: best ? AppColors.gradientGold : const [AppColors.accent2, AppColors.accent],
          ).createShader(rect.outerRect),
      );
      tops.add(Offset(rect.left + barW / 2, rect.top));
    }

    final draw = segment(intro, 0.45, 1);
    if (draw <= 0) return;

    final path = Path()..moveTo(tops.first.dx, tops.first.dy - 8);
    for (final p in tops.skip(1)) {
      path.lineTo(p.dx, p.dy - 8);
    }
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * draw),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor,
    );

    final head = metric.getTangentForOffset(metric.length * draw)?.position;
    if (head != null) {
      final pulse = 1 + 0.25 * math.sin(loop * 2 * math.pi * 2);
      canvas.drawCircle(head, 5.5 * pulse, Paint()..color = dotRing);
      canvas.drawCircle(head, 3.6 * pulse, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

// ---------------------------------------------------------------------------
// 3. Timeline — calls, WhatsApp, notes and follow-ups on one line.
// ---------------------------------------------------------------------------

class TimelineIllustration extends StatelessWidget {
  const TimelineIllustration({super.key, required this.active});

  final bool active;

  static const _events = [
    (Icons.call_rounded, AppColors.accent, 'Outbound call', 132.0),
    (Icons.chat_rounded, AppColors.success, 'WhatsApp message', 108.0),
    (Icons.sticky_note_2_rounded, AppColors.gold, 'Note added', 120.0),
    (Icons.event_available_rounded, AppColors.violet, 'Follow-up set', 96.0),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedIllustration(
      active: active,
      builder: (context, intro, loop) {
        const top = 36.0;
        const step = 62.0;
        final glowing = intro >= 0.95 ? (loop * _events.length).floor().clamp(0, _events.length - 1) : -1;
        final glowPhase = (loop * _events.length) % 1;

        return IllustrationStage(
          children: [
            Positioned(
              left: 61,
              top: top + 17,
              width: 2.5,
              height: step * (_events.length - 1) * segment(intro, 0, 0.6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            for (var i = 0; i < _events.length; i++)
              Positioned.fill(
                child: _TimelineRow(
                  icon: _events[i].$1,
                  color: _events[i].$2,
                  label: _events[i].$3,
                  skeleton: _events[i].$4,
                  y: top + i * step,
                  t: segment(intro, 0.12 + i * 0.16, 0.42 + i * 0.16),
                  glow: i == glowing ? glowPhase : null,
                  scheme: scheme,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.skeleton,
    required this.y,
    required this.t,
    required this.glow,
    required this.scheme,
  });

  final IconData icon;
  final Color color;
  final String label;
  final double skeleton;
  final double y;
  final double t;
  final double? glow;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (glow != null)
          Positioned(
            left: 62 - 17 - 10 * glow!,
            top: y - 10 * glow!,
            child: Container(
              width: 34 + 20 * glow!,
              height: 34 + 20 * glow!,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.28 * (1 - glow!))),
            ),
          ),
        Positioned(
          left: 45,
          top: y,
          child: Transform.scale(
            scale: t,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: scheme.surface, width: 3),
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          left: 92,
          top: y - 7,
          width: 178,
          height: 48,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset((1 - t) * 34, 0),
              child: Container(
                decoration: illustrationCard(context, radius: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurface),
                    ),
                    const SizedBox(height: 6),
                    SkeletonBar(width: skeleton),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Follow-ups — tasks tick off, the bell rings, outcome chips pop in.
// ---------------------------------------------------------------------------

class FollowUpsIllustration extends StatelessWidget {
  const FollowUpsIllustration({super.key, required this.active});

  final bool active;

  static const _tasks = ['Call back customer', 'Send quote on WhatsApp', 'Product demo'];

  static const _chips = [
    ('Interested', AppColors.success, 34.0),
    ('Callback', AppColors.gold, 132.0),
    ('Won', AppColors.accent, 218.0),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedIllustration(
      active: active,
      builder: (context, intro, loop) {
        // The bell rings in a short burst at the start of each loop.
        final ring = loop < 0.3 ? math.sin(loop * 2 * math.pi * 9) * 0.32 * (1 - loop / 0.3) : 0.0;
        return IllustrationStage(
          children: [
            Positioned(
              left: 34,
              top: 46,
              width: 232,
              height: 168,
              child: Opacity(
                opacity: segment(intro, 0, 0.25),
                child: Container(
                  decoration: illustrationCard(context),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's follow-ups",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: scheme.onSurface),
                      ),
                      const SizedBox(height: 10),
                      for (var i = 0; i < _tasks.length; i++)
                        Padding(
                          padding: EdgeInsets.only(bottom: i == _tasks.length - 1 ? 0 : 10),
                          child: _TaskRow(label: _tasks[i], checked: segment(intro, 0.2 + i * 0.2, 0.45 + i * 0.2)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 220,
              top: 24,
              child: Transform.scale(
                scale: segment(intro, 0.1, 0.5, Curves.elasticOut),
                child: Transform.rotate(
                  angle: ring,
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: AppColors.gradientGold,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(color: AppColors.gold.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < _chips.length; i++)
              Positioned(
                left: _chips[i].$3,
                top: 228 +
                    (1 - segment(intro, 0.65 + i * 0.1, 0.95 + i * 0.05, Curves.easeOutBack)) * 20 +
                    math.sin((loop + i * 0.33) * 2 * math.pi) * 2.5,
                child: Opacity(
                  opacity: segment(intro, 0.65 + i * 0.1, 0.9 + i * 0.05),
                  child: _OutcomeChip(label: _chips[i].$1, color: _chips[i].$2),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.label, required this.checked});

  final String label;
  final double checked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Color.lerp(Colors.transparent, AppColors.success, checked),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Color.lerp(scheme.outline, AppColors.success, checked)!, width: 1.6),
          ),
          child: CustomPaint(painter: _CheckPainter(checked)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color.lerp(scheme.onSurface, scheme.onSurfaceVariant, checked),
              decoration: checked > 0.6 ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.24, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.30);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Team — live agent statuses and a login-time breakdown bar.
// ---------------------------------------------------------------------------

class TeamIllustration extends StatelessWidget {
  const TeamIllustration({super.key, required this.active});

  final bool active;

  static const _agents = [
    ('A', AppColors.accent, 'On call', AppColors.success, 70.0),
    ('R', AppColors.violet, 'Idle', AppColors.cold, 56.0),
    ('S', AppColors.pink, 'Break', AppColors.gold, 64.0),
  ];

  // Talk, wrap-up, break, idle — as fractions of login time.
  static const _split = [
    (0.42, AppColors.accent, 'Talk'),
    (0.12, AppColors.violet, 'Wrap-up'),
    (0.16, AppColors.gold, 'Break'),
    (0.30, AppColors.cold, 'Idle'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedIllustration(
      active: active,
      builder: (context, intro, loop) {
        final blink = 0.5 + 0.5 * math.sin(loop * 2 * math.pi * 2);
        final grow = segment(intro, 0.5, 1);

        return IllustrationStage(
          children: [
            Positioned(
              left: 32,
              top: 34,
              width: 236,
              height: 138,
              child: Opacity(
                opacity: segment(intro, 0, 0.25),
                child: Container(
                  decoration: illustrationCard(context),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text('Team', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: scheme.onSurface)),
                          const Spacer(),
                          _LivePill(blink: blink),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (var i = 0; i < _agents.length; i++)
                        Expanded(
                          child: _AgentRow(
                            initial: _agents[i].$1,
                            color: _agents[i].$2,
                            status: _agents[i].$3,
                            statusColor: _agents[i].$4,
                            skeleton: _agents[i].$5,
                            t: segment(intro, 0.15 + i * 0.14, 0.45 + i * 0.14),
                            pulse: i == 0 ? blink : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 32,
              top: 190,
              width: 236,
              height: 78,
              child: Opacity(
                opacity: segment(intro, 0.3, 0.6),
                child: Container(
                  decoration: illustrationCard(context),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Login time', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: scheme.onSurface)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 12,
                          child: Row(
                            children: [
                              for (final s in _split)
                                Expanded(
                                  flex: (s.$1 * 100).round(),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: grow,
                                      child: ColoredBox(color: s.$2, child: const SizedBox.expand()),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Scales down instead of overflowing on narrow screens
                      // or with a large system font.
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Opacity(
                            opacity: grow,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final s in _split) ...[
                                  Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: s.$2)),
                                  const SizedBox(width: 4),
                                  Text(
                                    s.$3,
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                                  ),
                                  if (s != _split.last) const SizedBox(width: 12),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.blink});

  final double blink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.danger.withValues(alpha: 0.35 + 0.65 * blink)),
          ),
          const SizedBox(width: 4),
          const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.danger)),
        ],
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.initial,
    required this.color,
    required this.status,
    required this.statusColor,
    required this.skeleton,
    required this.t,
    required this.pulse,
  });

  final String initial;
  final Color color;
  final String status;
  final Color statusColor;
  final double skeleton;
  final double t;

  /// 0..1 blink for a live "on call" dot; null for a steady dot.
  final double? pulse;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset((1 - t) * 24, 0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: color,
              child: Text(initial, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(width: 10),
            SkeletonBar(width: skeleton),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor.withValues(alpha: pulse == null ? 1 : 0.4 + 0.6 * pulse!),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
