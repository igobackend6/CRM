import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leads/domain/allocation_range.dart';
import 'package:mobile/features/leads/domain/entities/lead_filters.dart';

void main() {
  // Wednesday 2026-09-23.
  final now = DateTime(2026, 9, 23, 15, 40);

  group('allocationRangeOf', () {
    test('no dates is Overall', () {
      expect(allocationRangeOf(const LeadFilters.empty(), now), AllocationRange.overall);
    });

    test('a lower bound 30 days back with no upper bound is Last 30 Days', () {
      final filters = const LeadFilters.empty().withDates(from: last30DaysStart(now));

      expect(allocationRangeOf(filters, now), AllocationRange.last30Days);
    });

    test('any other window, or one with an upper bound, is a custom range', () {
      expect(
        allocationRangeOf(const LeadFilters.empty().withDates(from: DateTime(2026, 9, 1), to: endOfDay(DateTime(2026, 9, 5))), now),
        AllocationRange.custom,
      );
      expect(allocationRangeOf(const LeadFilters.empty().withDates(from: DateTime(2026, 9, 1)), now), AllocationRange.custom);
      expect(allocationRangeOf(const LeadFilters.empty().withDates(to: DateTime(2026, 9, 1)), now), AllocationRange.custom);
    });
  });

  test('last30DaysStart is local midnight 30 days back, across a month boundary', () {
    expect(last30DaysStart(now), DateTime(2026, 8, 24));
    expect(last30DaysStart(DateTime(2026, 3, 5, 9)), DateTime(2026, 2, 3));
  });

  test('endOfDay is the last second of that day', () {
    expect(endOfDay(DateTime(2026, 9, 5, 7, 3)), DateTime(2026, 9, 5, 23, 59, 59));
  });

  test('allocationRangeLabel writes "12 Sep – 24 Sep", with Any for an open side', () {
    expect(allocationRangeLabel(const LeadFilters.empty().withDates(from: DateTime(2026, 9, 12), to: DateTime(2026, 9, 24))), '12 Sep – 24 Sep');
    expect(allocationRangeLabel(const LeadFilters.empty().withDates(from: DateTime(2026, 9, 12))), '12 Sep – Any');
    expect(allocationRangeLabel(const LeadFilters.empty().withDates(to: DateTime(2026, 9, 24))), 'Any – 24 Sep');
  });

  group('LeadFilters.withStatus / withDates', () {
    const base = LeadFilters(statusId: 's1', sourceId: 'src', priority: 'high', isCustomer: false, tagId: 't1');

    test('withStatus changes only the status', () {
      final next = base.withStatus('s2');

      expect(next.statusId, 's2');
      expect(next.sourceId, 'src');
      expect(next.priority, 'high');
      expect(next.isCustomer, false);
      expect(next.tagId, 't1');
    });

    test('withStatus(null) clears just the status', () {
      expect(base.withStatus(null).statusId, isNull);
      expect(base.withStatus(null).priority, 'high');
    });

    test('withDates changes only the dates, and no arguments clears them', () {
      final dated = base.withDates(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 2));

      expect(dated.createdFrom, DateTime(2026, 9, 1));
      expect(dated.createdTo, DateTime(2026, 9, 2));
      expect(dated.statusId, 's1');
      expect(dated.withDates().createdFrom, isNull);
      expect(dated.withDates().createdTo, isNull);
    });
  });
}
