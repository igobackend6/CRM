import 'package:flutter/material.dart';

import '../../features/customer360/domain/entities/timeline_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'meta_row.dart';

/// One entry of a unified activity feed (Phase 8 Customer 360 timeline;
/// Phase 15 generalizes the same [TimelineItem] to Lead Detail too) —
/// shared here so both screens render activity identically instead of
/// each keeping its own copy of the icon/color mapping and tile layout.
const Map<String, IconData> _activityIcons = {
  'call': Icons.call_outlined,
  'note': Icons.sticky_note_2_outlined,
  'status_change': Icons.swap_horiz,
  'document': Icons.insert_drive_file_outlined,
  'follow_up': Icons.event_note_outlined,
  'message': Icons.message_outlined,
  'allocation': Icons.person_pin_circle_outlined,
};

// A distinct color per activity category — the multi-hue icon rail seen
// throughout the real app's UI (docs/design/design-tokens.md) rather
// than every event type looking identical.
const Map<String, Color> _activityColors = {
  'call': AppColors.brandOrange,
  'note': Color(0xFF0065F2),
  'status_change': Color(0xFF5E33EC),
  'document': AppColors.success,
  'follow_up': AppColors.actionRed,
  'message': Color(0xFF0065F2),
  'allocation': AppColors.brandInk,
};

String formatDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// A short "2h ago"/"3d ago" label for recent activity, falling back to
/// the plain date once an item is old enough that a relative label stops
/// being useful (Phase 15 §"relative time where useful" — not "always").
String formatRelativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDateTime(date);
}

/// Type-specific extra detail (Phase 15 §"Flutter Activity UI": "call
/// outcome/duration when applicable, follow-up status when applicable,
/// allocation assignee when applicable") — returns null when [item]'s
/// type has nothing extra to add beyond the summary/actor/time every
/// tile already shows.
MetaItem? _extraDetail(TimelineItem item) {
  switch (item.type) {
    case 'call':
      final seconds = item.details['duration_seconds'] as int?;
      final state = item.details['state'] as String?;
      final parts = [
        ?state,
        if (seconds != null) '${seconds}s',
      ];
      return parts.isEmpty ? null : MetaItem(Icons.timer_outlined, parts.join(' • '));
    case 'follow_up':
      final status = item.details['status'] as String?;
      return status == null ? null : MetaItem(Icons.flag_outlined, status);
    case 'allocation':
      final assignee = (item.details['assigned_member'] as Map?)?.cast<String, dynamic>();
      final name = assignee?['full_name'] as String? ?? (assignee != null ? 'Unknown' : null);
      return name == null ? null : MetaItem(Icons.person_outline, name);
    default:
      return null;
  }
}

/// Renders one [TimelineItem]. [onTap] is provided by the caller — it
/// alone decides where a call/follow-up activity navigates (Phase 15
/// §"Activity Navigation": call -> existing Call Detail, follow-up ->
/// existing Follow-Up Detail; this widget has no routing knowledge of
/// its own, keeping it usable from any screen).
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.item, this.onTap});

  final TimelineItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = _activityColors[item.type] ?? Theme.of(context).colorScheme.outline;
    final extra = _extraDetail(item);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(_activityIcons[item.type] ?? Icons.history, size: 16, color: color),
      ),
      title: Text(item.summary),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.actorMember?.fullName ?? 'System'),
          if (extra != null) ...[const SizedBox(height: AppSpacing.xs), MetaRow(items: [extra])],
        ],
      ),
      isThreeLine: extra != null,
      trailing: Text(formatRelativeTime(item.occurredAt), style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
