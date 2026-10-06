import '../../reports/domain/entities/call_trends.dart';

/// The rows behind the chart as CSV — one line per bucket, with the
/// bucket start in the user's *local* time (that's the clock the chart
/// axis shows), so an export opened next to the screen lines up.
String callTrendsCsv(CallTrends trends) {
  String pad(int n) => n.toString().padLeft(2, '0');
  String local(DateTime utc) {
    final t = utc.toLocal();
    return '${t.year}-${pad(t.month)}-${pad(t.day)} ${pad(t.hour)}:${pad(t.minute)}';
  }

  final lines = ['bucket_start,calls,unique_leads,talk_time_seconds'];
  for (final bucket in trends.buckets) {
    lines.add('${local(bucket.start)},${bucket.calls},${bucket.uniqueLeads},${bucket.talkTimeSeconds}');
  }
  return '${lines.join('\n')}\n';
}
