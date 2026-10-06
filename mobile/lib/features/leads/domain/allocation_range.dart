import 'entities/lead_filters.dart';

/// The three date chips under the Allocations header. They are views over
/// the list's existing created-date filter (`LeadFilters.createdFrom/To`),
/// so the filter sheet's own From/To dates and these chips always agree —
/// there is no second piece of state to fall out of sync.
enum AllocationRange { overall, last30Days, custom }

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Local midnight 30 days before [now]'s date — the start of "Last 30 Days".
DateTime last30DaysStart(DateTime now) => DateTime(now.year, now.month, now.day - 30);

/// End of [day] (23:59:59) — so a picked range's last day is included.
DateTime endOfDay(DateTime day) => DateTime(day.year, day.month, day.day, 23, 59, 59);

/// Which chip the filters currently correspond to.
AllocationRange allocationRangeOf(LeadFilters filters, DateTime now) {
  final from = filters.createdFrom;
  final to = filters.createdTo;
  if (from == null && to == null) return AllocationRange.overall;
  if (to == null && from != null && _dateOnly(from) == last30DaysStart(now)) return AllocationRange.last30Days;
  return AllocationRange.custom;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _short(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// "12 Sep – 24 Sep" for the custom chip (open-ended sides read as "Any").
String allocationRangeLabel(LeadFilters filters) {
  final from = filters.createdFrom;
  final to = filters.createdTo;
  return '${from == null ? 'Any' : _short(from)} – ${to == null ? 'Any' : _short(to)}';
}
