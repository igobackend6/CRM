import 'package:flutter/material.dart';

/// One label/value row on a detail screen (Phone, Email, Status, ...) —
/// replaces the `_InfoRow` private widget that used to be duplicated
/// nearly verbatim in lead/follow-up/call/customer detail screens.
/// `trailing` covers the one place a plain label/value pair wasn't
/// enough (Lead Detail's "Assigned to" row, which also has a
/// Change/Assign action).
class DetailInfoRow extends StatelessWidget {
  const DetailInfoRow({super.key, required this.label, required this.value, this.trailing, this.valueColor});

  final String label;
  final String value;
  final Widget? trailing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(child: Text(value, style: valueColor != null ? TextStyle(color: valueColor) : null)),
          ?trailing,
        ],
      ),
    );
  }
}
