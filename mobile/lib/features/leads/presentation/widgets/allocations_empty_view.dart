import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// The Allocations tab's empty state: three faded list rows with avatars
/// (the reference's illustration, drawn in our palette) over a title and a
/// line telling the member where allocations come from.
class AllocationsEmptyView extends StatelessWidget {
  const AllocationsEmptyView({super.key, required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Illustration(),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textHeading),
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration();

  @override
  Widget build(BuildContext context) {
    const dots = [AppColors.success, AppColors.gold, AppColors.sky];
    return ExcludeSemantics(
      child: SizedBox(
        width: 180,
        height: 150,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < 3; i++)
              Positioned(
                left: 0,
                right: 14,
                top: i * 48.0,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.standard),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 5,
                        width: 84,
                        decoration: BoxDecoration(color: AppColors.accentBg, borderRadius: BorderRadius.circular(3)),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 5,
                        width: 52,
                        decoration: BoxDecoration(color: AppColors.accentBg, borderRadius: BorderRadius.circular(3)),
                      ),
                    ],
                  ),
                ),
              ),
            for (var i = 0; i < 3; i++)
              Positioned(
                right: 0,
                top: i * 48.0 - 4,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: dots[i].withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.person, size: 18, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
