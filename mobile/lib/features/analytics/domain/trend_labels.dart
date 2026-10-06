import '../../reports/domain/entities/call_trends.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _hour12(int hour) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h${hour < 12 ? 'a' : 'p'}';
}

String _clock(int hour) => '${hour % 12 == 0 ? 12 : hour % 12}:00 ${hour < 12 ? 'AM' : 'PM'}';

/// One x-axis label per bucket, blank where the axis would get crowded:
/// hourly bars are labelled every 6 hours (12a 6a 12p 6p), a week's daily
/// bars all get their weekday, and a month's daily bars every 5th day.
/// Buckets are shown in the *user's* local time (`start` arrives as UTC).
List<String> trendAxisLabels(CallTrends trends) {
  final buckets = trends.buckets;
  return [
    for (var i = 0; i < buckets.length; i++)
      () {
        final local = buckets[i].start.toLocal();
        if (trends.granularity == CallTrendGranularity.hour) {
          return local.hour % 6 == 0 ? _hour12(local.hour) : '';
        }
        if (buckets.length <= 7) return _weekdays[local.weekday - 1];
        return i % 5 == 0 ? '${local.day}' : '';
      }(),
  ];
}

/// The caption for one bar — "9:00 AM – 10:00 AM" or "Mon 21 Sep".
String bucketTimeLabel(CallTrendBucket bucket, CallTrendGranularity granularity) {
  final local = bucket.start.toLocal();
  if (granularity == CallTrendGranularity.hour) {
    // `% 24` so the 11 PM bar ends at 12:00 AM, not "12:00 PM".
    return '${_clock(local.hour)} – ${_clock((local.hour + 1) % 24)}';
  }
  return '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}';
}
