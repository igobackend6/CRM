import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/chart_axis.dart';

/// A vertical bar chart drawn with `CustomPainter` (this app deliberately
/// has no charting dependency — see Phase 11). [values] are already in the
/// unit the axis should show; [yLabel] formats a tick, [xLabels] holds one
/// label per bar (an empty string leaves that bar unlabelled, so callers
/// decide the density), and [describe] gives the caption shown when a bar
/// is tapped.
class AnalyticsBarChart extends StatefulWidget {
  const AnalyticsBarChart({
    super.key,
    required this.values,
    required this.xLabels,
    required this.yLabel,
    required this.describe,
    this.color = AppColors.accent,
    this.height = 180,
    this.wholeNumbers = false,
  });

  final List<double> values;
  final List<String> xLabels;
  final String Function(double value) yLabel;
  final String Function(int index) describe;
  final Color color;
  final double height;

  /// True for counts: the y-axis then never steps by less than 1.
  final bool wholeNumbers;

  @override
  State<AnalyticsBarChart> createState() => _AnalyticsBarChartState();
}

class _AnalyticsBarChartState extends State<AnalyticsBarChart> {
  int? _selected;

  static const _leftGutter = 36.0;
  static const _bottomGutter = 22.0;
  static const _topPadding = 8.0;

  void _select(Offset local, double width) {
    final plotWidth = width - _leftGutter;
    if (plotWidth <= 0 || widget.values.isEmpty) return;
    final index = ((local.dx - _leftGutter) / (plotWidth / widget.values.length)).floor();
    setState(() => _selected = index >= 0 && index < widget.values.length && index != _selected ? index : null);
  }

  @override
  void didUpdateWidget(AnalyticsBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != null && _selected! >= widget.values.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: selected == null
              ? Text('Tap a bar for details', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim))
              : Text(widget.describe(selected), style: theme.textTheme.labelMedium),
        ),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _select(details.localPosition, constraints.maxWidth),
            child: CustomPaint(
              size: Size(constraints.maxWidth, widget.height),
              painter: _BarChartPainter(
                values: widget.values,
                xLabels: widget.xLabels,
                yLabel: widget.yLabel,
                color: widget.color,
                wholeNumbers: widget.wholeNumbers,
                selected: selected,
                gridColor: theme.colorScheme.outline,
                labelStyle: theme.textTheme.labelSmall?.copyWith(color: AppColors.textDim) ?? const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.xLabels,
    required this.yLabel,
    required this.color,
    required this.wholeNumbers,
    required this.selected,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<double> values;
  final List<String> xLabels;
  final String Function(double) yLabel;
  final Color color;
  final bool wholeNumbers;
  final int? selected;
  final Color gridColor;
  final TextStyle labelStyle;

  void _text(Canvas canvas, String text, Offset anchor, {required bool rightAligned, required bool centered}) {
    final painter = TextPainter(text: TextSpan(text: text, style: labelStyle), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    var dx = anchor.dx;
    if (rightAligned) dx -= painter.width;
    if (centered) dx -= painter.width / 2;
    painter.paint(canvas, Offset(dx, anchor.dy - painter.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = _AnalyticsBarChartState._leftGutter;
    const bottom = _AnalyticsBarChartState._bottomGutter;
    const top = _AnalyticsBarChartState._topPadding;

    final plot = Rect.fromLTRB(left, top, size.width, size.height - bottom);
    final axis = niceChartAxis(values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b), minStep: wholeNumbers ? 1 : 0);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final tick in axis.ticks) {
      final y = plot.bottom - plot.height * (tick / axis.top);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(canvas, yLabel(tick), Offset(plot.left - 6, y), rightAligned: true, centered: false);
    }

    if (values.isEmpty) return;
    final slot = plot.width / values.length;
    final barWidth = (slot * 0.62).clamp(2.0, 28.0);
    for (var i = 0; i < values.length; i++) {
      final centerX = plot.left + slot * (i + 0.5);
      if (values[i] > 0) {
        final barHeight = (plot.height * (values[i] / axis.top)).clamp(2.0, plot.height);
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(centerX - barWidth / 2, plot.bottom - barHeight, barWidth, barHeight),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rect, Paint()..color = selected == null || selected == i ? color : color.withValues(alpha: 0.35));
      }
      if (i < xLabels.length && xLabels[i].isNotEmpty) {
        _text(canvas, xLabels[i], Offset(centerX, plot.bottom + bottom / 2 + 2), rightAligned: false, centered: true);
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.values != values || old.xLabels != xLabels || old.color != color || old.selected != selected || old.gridColor != gridColor;
}
