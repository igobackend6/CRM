import '../../reports/domain/entities/call_trends.dart';

enum AnalyticsPeriodKind { day, week, month }

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String monthName(int month) => _monthNames[month - 1];

String _shortMonth(int month) => _monthNames[month - 1].substring(0, 3);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The window the Call Analytics screen shows: one local calendar day,
/// Monday-start week, or month — the Day/Week/Month tabs of the period
/// sheet. `since`/`until` are the *instants* of the local midnight
/// boundaries, which is what the backend buckets from (see
/// ReportService.get_call_trends), so "today" means the user's own day
/// regardless of the server's timezone.
///
/// All date arithmetic goes through the `DateTime(y, m, d)` constructor
/// rather than `add/subtract(Duration)`: a local day is 23 or 25 hours
/// across a DST change, and duration math would land on 23:00/01:00 of
/// the neighbouring day instead of that day's midnight.
class CallAnalyticsPeriod {
  const CallAnalyticsPeriod._(this.kind, this.start);

  factory CallAnalyticsPeriod.day(DateTime date) => CallAnalyticsPeriod._(AnalyticsPeriodKind.day, _dateOnly(date));

  factory CallAnalyticsPeriod.week(DateTime date) =>
      CallAnalyticsPeriod._(AnalyticsPeriodKind.week, DateTime(date.year, date.month, date.day - (date.weekday - 1)));

  factory CallAnalyticsPeriod.month(DateTime date) => CallAnalyticsPeriod._(AnalyticsPeriodKind.month, DateTime(date.year, date.month));

  factory CallAnalyticsPeriod.today([DateTime? now]) => CallAnalyticsPeriod.day(now ?? DateTime.now());

  final AnalyticsPeriodKind kind;

  /// Local midnight that opens the period (a Monday for weeks, the 1st for
  /// months).
  final DateTime start;

  /// Local midnight that closes the period — exclusive.
  DateTime get end => switch (kind) {
        AnalyticsPeriodKind.day => DateTime(start.year, start.month, start.day + 1),
        AnalyticsPeriodKind.week => DateTime(start.year, start.month, start.day + 7),
        AnalyticsPeriodKind.month => DateTime(start.year, start.month + 1),
      };

  /// UTC instant of [start] — the backend's `since`.
  DateTime get since => start.toUtc();

  /// UTC instant of [end] — the backend's `until`.
  DateTime get until => end.toUtc();

  /// A single day is charted per hour; a week or month per day.
  CallTrendGranularity get granularity => kind == AnalyticsPeriodKind.day ? CallTrendGranularity.hour : CallTrendGranularity.day;

  /// Whether this period is the one containing [now].
  bool isCurrent(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  /// The same-kind period that is [steps] periods away (negative = past).
  CallAnalyticsPeriod shifted(int steps) => switch (kind) {
        AnalyticsPeriodKind.day => CallAnalyticsPeriod.day(DateTime(start.year, start.month, start.day + steps)),
        AnalyticsPeriodKind.week => CallAnalyticsPeriod.week(DateTime(start.year, start.month, start.day + 7 * steps)),
        AnalyticsPeriodKind.month => CallAnalyticsPeriod.month(DateTime(start.year, start.month + steps)),
      };

  /// The text on the period dropdown: "Today"/"This week"/"This month"
  /// while it is the current period, otherwise the concrete dates.
  String label(DateTime now) {
    switch (kind) {
      case AnalyticsPeriodKind.day:
        if (isCurrent(now)) return 'Today';
        if (CallAnalyticsPeriod.day(now).shifted(-1) == this) return 'Yesterday';
        return start.year == now.year ? '${start.day} ${_shortMonth(start.month)}' : '${start.day} ${_shortMonth(start.month)} ${start.year}';
      case AnalyticsPeriodKind.week:
        if (isCurrent(now)) return 'This week';
        final last = DateTime(start.year, start.month, start.day + 6);
        return '${start.day} ${_shortMonth(start.month)} – ${last.day} ${_shortMonth(last.month)}';
      case AnalyticsPeriodKind.month:
        if (isCurrent(now)) return 'This month';
        return start.year == now.year ? monthName(start.month) : '${_shortMonth(start.month)} ${start.year}';
    }
  }

  @override
  bool operator ==(Object other) => other is CallAnalyticsPeriod && other.kind == kind && other.start == start;

  @override
  int get hashCode => Object.hash(kind, start);
}
