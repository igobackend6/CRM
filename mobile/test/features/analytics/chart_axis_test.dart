import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/domain/chart_axis.dart';

void main() {
  group('niceChartAxis', () {
    test('an empty or all-zero series still gets a usable 0..4 axis', () {
      final axis = niceChartAxis(0);

      expect(axis.top, 4);
      expect(axis.ticks, [0, 1, 2, 3, 4]);
    });

    test('small counts step by 1', () {
      final axis = niceChartAxis(3);

      expect(axis.step, 1);
      expect(axis.top, 4);
    });

    test('rounds the step up to 1, 2 or 5 times a power of ten', () {
      expect(niceChartAxis(7).step, 2); // raw 1.75 -> 2
      expect(niceChartAxis(18).step, 5); // raw 4.5 -> 5
      expect(niceChartAxis(35).step, 10); // raw 8.75 -> 10
      expect(niceChartAxis(120).step, 50); // raw 30 -> 50
    });

    test('the top gridline always covers the largest value', () {
      for (final max in [1.0, 2.0, 5.0, 9.0, 13.0, 47.0, 99.0, 101.0, 999.0, 1234.0]) {
        expect(niceChartAxis(max).top, greaterThanOrEqualTo(max), reason: 'max=$max');
      }
    });

    test('minStep keeps count axes on whole numbers even for a tiny max', () {
      final axis = niceChartAxis(1, minStep: 1);

      expect(axis.step, 1);
      expect(axis.ticks, [0, 1, 2, 3, 4]);
      // Without the floor the same series would step by 0.5.
      expect(niceChartAxis(1).step, 0.5);
    });

    test('fractional maxima (talk time in hours) get a fractional step', () {
      final axis = niceChartAxis(0.8);

      expect(axis.step, 0.2);
      expect(axis.top, closeTo(0.8, 1e-9));
    });
  });

  group('durationUnitFor', () {
    test('picks seconds, minutes, then hours as the largest bar grows', () {
      expect(durationUnitFor(45).suffix, 's');
      expect(durationUnitFor(120).suffix, 's');
      expect(durationUnitFor(121).suffix, 'm');
      expect(durationUnitFor(7200).suffix, 'm');
      expect(durationUnitFor(7201).suffix, 'h');
    });

    test('converts seconds into the chosen unit', () {
      expect(durationUnitFor(600).convert(300), 5); // minutes
      expect(durationUnitFor(20000).convert(7200), 2); // hours
    });

    test('labels whole numbers without a decimal and fractions with one', () {
      final minutes = durationUnitFor(600);

      expect(minutes.label(5), '5m');
      expect(minutes.label(2.5), '2.5m');
    });
  });
}
