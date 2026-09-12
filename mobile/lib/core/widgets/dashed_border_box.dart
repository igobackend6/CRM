import 'package:flutter/material.dart';

import '../theme/app_radius.dart';

/// A tappable box with a dashed border — the "Upload Documents" drop
/// zone from the Runo reference (docs/design/design-tokens.md).
/// Flutter's own `Border` only draws solid or no border, so this paints
/// the dashes itself via [CustomPainter] rather than pulling in a
/// package for one shape.
class DashedBorderBox extends StatelessWidget {
  const DashedBorderBox({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: Theme.of(context).colorScheme.outline),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;
  static const _dashWidth = 6.0;
  static const _dashSpace = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(AppRadius.standard));
    final metric = (Path()..addRRect(rrect)).computeMetrics().first;

    var distance = 0.0;
    while (distance < metric.length) {
      final next = distance + _dashWidth;
      canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
      distance = next + _dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
