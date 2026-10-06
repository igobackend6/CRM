/// "3:05 PM" — a wall-clock time in the device's local zone (12-hour, no
/// leading zero on the hour, matching how the rest of the app writes
/// times).
String formatClock(DateTime moment) {
  final local = moment.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}
