import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Circular initials avatar for a person/lead/contact name — the avatar
/// circles seen next to contact names throughout Runo's UI
/// (docs/design/design-tokens.md). Color is deterministic (a hash of the
/// name into a small on-brand palette), not random, so the same name
/// always gets the same color across screens/rebuilds.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 40});

  final String? name;
  final double size;

  static const List<Color> _palette = [
    AppColors.brandOrange,
    AppColors.brandInk,
    AppColors.actionRed,
    Color(0xFF5E33EC), // violet — accentGradient's middle stop
    Color(0xFF0065F2), // blue — accentGradient's end stop
    AppColors.success,
  ];

  String get _initials {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Color get _backgroundColor {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return AppColors.textTertiary;
    final hash = trimmed.codeUnits.fold<int>(0, (acc, c) => acc + c);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _backgroundColor,
      child: Text(
        _initials,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
