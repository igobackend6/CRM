import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_typography.dart';

/// Semantic tone for [AppStatusChip] — maps to a real, distinguishable
/// color rather than every status/outcome looking like an identical
/// gray `Chip`.
enum ChipTone { neutral, positive, warning, negative, info }

/// A small pill badge for a lead status, follow-up status, call outcome,
/// or tag — colored by semantic meaning rather than the flat, uncolored
/// `Chip(label: Text(...))` this replaces everywhere. Radius/weight
/// follow the real tokens in docs/design/design-tokens.md.
class AppStatusChip extends StatelessWidget {
  const AppStatusChip({super.key, required this.label, this.tone = ChipTone.neutral, this.icon, this.color});

  final String label;
  final ChipTone tone;
  final IconData? icon;

  /// An explicit override color (e.g. a workspace-configured tag color)
  /// — takes precedence over [tone] when set.
  final Color? color;

  Color _toneColor(BuildContext context) {
    if (color != null) return color!;
    switch (tone) {
      case ChipTone.positive:
        return AppColors.success;
      case ChipTone.warning:
        return AppColors.warning;
      case ChipTone.negative:
        return Theme.of(context).colorScheme.error;
      case ChipTone.info:
        return const Color(0xFF0065F2); // accentGradient's blue stop
      case ChipTone.neutral:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final toneColor = _toneColor(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: toneColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: toneColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: toneColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Derives a tone from a lead status's pipeline `stage` — the only
  /// semantic signal `LeadStatus` carries (its `name`/`code` are
  /// workspace-configurable free text). `closed_won` is positive,
  /// `closed_lost` negative; `start`/`in_progress` stay neutral.
  factory AppStatusChip.forLeadStatus({required String name, required String stage}) {
    final tone = switch (stage) {
      'closed_won' => ChipTone.positive,
      'closed_lost' => ChipTone.negative,
      _ => ChipTone.neutral,
    };
    return AppStatusChip(label: name, tone: tone);
  }

  /// Derives a tone from a call outcome's `isPositive` flag.
  factory AppStatusChip.forCallOutcome({required String name, required bool isPositive}) {
    return AppStatusChip(label: name, tone: isPositive ? ChipTone.positive : ChipTone.neutral);
  }

  /// Derives a tone from a follow-up's status string + overdue flag.
  factory AppStatusChip.forFollowUpStatus({required String status, bool isOverdue = false}) {
    switch (status) {
      case 'completed':
        return AppStatusChip(label: status, tone: ChipTone.positive);
      case 'cancelled':
        return AppStatusChip(label: status, tone: ChipTone.neutral);
      default:
        return AppStatusChip(label: status, tone: isOverdue ? ChipTone.warning : ChipTone.info);
    }
  }

  /// Derives a tone from an AI call insight's sentiment string (Phase 20
  /// — `ai_call_insights.sentiment`'s own CHECK constraint: positive/
  /// neutral/negative).
  factory AppStatusChip.forSentiment(String sentiment) {
    switch (sentiment) {
      case 'positive':
        return AppStatusChip(label: sentiment, tone: ChipTone.positive);
      case 'negative':
        return AppStatusChip(label: sentiment, tone: ChipTone.negative);
      default:
        return AppStatusChip(label: sentiment, tone: ChipTone.neutral);
    }
  }
}
