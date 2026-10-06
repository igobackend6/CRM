/// A y-axis for a bar chart: `top` is the value of the highest gridline and
/// `step` the distance between gridlines, so the axis always has `divisions`
/// evenly spaced whole-number-friendly ticks (0, step, 2*step, ... top).
class ChartAxis {
  const ChartAxis({required this.top, required this.step, required this.divisions});

  final double top;
  final double step;
  final int divisions;

  List<double> get ticks => [for (var i = 0; i <= divisions; i++) step * i];
}

/// Picks a "nice" axis (steps of 1, 2, 5 × a power of ten) that covers
/// [maxValue] with [divisions] gridlines. An all-zero series still gets a
/// usable 0..divisions axis rather than a zero-height one. [minStep] stops
/// the step going below a floor — counts pass 1 so a chart of "1 call"
/// gets ticks 0,1,2,3,4 instead of 0.5 steps that would round to
/// duplicate labels.
ChartAxis niceChartAxis(double maxValue, {int divisions = 4, double minStep = 0}) {
  if (maxValue <= 0) return ChartAxis(top: divisions * (minStep > 1 ? minStep : 1), step: minStep > 1 ? minStep : 1, divisions: divisions);

  final rawStep = maxValue / divisions;
  var magnitude = 1.0;
  while (magnitude * 10 <= rawStep) {
    magnitude *= 10;
  }
  while (magnitude > rawStep) {
    magnitude /= 10;
  }

  final residual = rawStep / magnitude;
  final niceResidual = residual <= 1 ? 1 : (residual <= 2 ? 2 : (residual <= 5 ? 5 : 10));
  final step = niceResidual * magnitude < minStep ? minStep : niceResidual * magnitude;
  return ChartAxis(top: step * divisions, step: step, divisions: divisions);
}

/// The unit a talk-time axis is drawn in — chosen from the largest bar so
/// a day of 30-second calls reads "30s" and a month of long calls reads
/// "2h", rather than every chart being forced into minutes.
class DurationUnit {
  const DurationUnit({required this.divisor, required this.suffix});

  final double divisor;
  final String suffix;

  double convert(int seconds) => seconds / divisor;

  /// An axis tick like `5m` or `1.5h` (one decimal only when needed).
  String label(double value) {
    final text = value == value.roundToDouble() ? value.round().toString() : value.toStringAsFixed(1);
    return '$text$suffix';
  }
}

DurationUnit durationUnitFor(int maxSeconds) {
  if (maxSeconds <= 120) return const DurationUnit(divisor: 1, suffix: 's');
  if (maxSeconds <= 7200) return const DurationUnit(divisor: 60, suffix: 'm');
  return const DurationUnit(divisor: 3600, suffix: 'h');
}
