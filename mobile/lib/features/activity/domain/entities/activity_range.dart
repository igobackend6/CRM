import '../../../analytics/domain/call_analytics_period.dart';

/// The window choices on the Login Analytics dropdown. Each resolves to a
/// local-calendar `CallAnalyticsPeriod`, so "Today" is the member's own
/// day (the backend is given the instants of their local midnights).
enum ActivityRange {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  thisMonth('This month');

  const ActivityRange(this.label);

  final String label;

  CallAnalyticsPeriod period(DateTime now) => switch (this) {
        ActivityRange.today => CallAnalyticsPeriod.day(now),
        ActivityRange.yesterday => CallAnalyticsPeriod.day(now).shifted(-1),
        ActivityRange.thisWeek => CallAnalyticsPeriod.week(now),
        ActivityRange.thisMonth => CallAnalyticsPeriod.month(now),
      };
}
