/// "4m 14s" / "1h 5m" — talk/idle-style durations on the analytics tiles.
/// Under an hour keeps the seconds (a 45s call must not read "0m"); from an
/// hour up the seconds are noise, so it switches to hours + minutes.
String formatTalkTime(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m ${total % 60}s';
}
