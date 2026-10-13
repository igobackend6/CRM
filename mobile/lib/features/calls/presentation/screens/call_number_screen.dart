import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../call_sync/presentation/providers/call_sync_providers.dart';
import '../../domain/entities/call_list_state.dart';
import '../providers/call_providers.dart';
import 'call_list_screen.dart' show CallTile;

/// The page behind a call's (i) icon, like the phone's own contact-info page: who the number is (the
/// lead, the name the phone has for it, or "Unknown"), its latest call log, and "View all" for every
/// call to/from the number. Only calls the CRM logged (the selected SIM's) are listed.
class CallNumberScreen extends ConsumerWidget {
  const CallNumberScreen({super.key, required this.phone});

  /// The last 10 digits of the number.
  final String phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(phoneCallListControllerProvider(phone));
    final theme = Theme.of(context);
    final latest = state.items.isEmpty ? null : state.items.first;
    final recordings = latest == null ? const {} : ref.watch(callRecordingsProvider(latest.id)).valueOrNull ?? const {};

    return Scaffold(
      appBar: brandAppBar(title: const Text('Number')),
      body: switch (state.status) {
        CallListStatus.initial || CallListStatus.loading => const Center(child: CircularProgressIndicator()),
        CallListStatus.error => AppRetryView(
            message: state.errorMessage ?? 'Could not load this number\'s calls.',
            onRetry: () => ref.read(phoneCallListControllerProvider(phone).notifier).refresh(),
          ),
        _ when latest == null => const EmptyStateView(icon: Icons.call_outlined, message: 'No calls logged for this number.'),
        _ => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SizedBox(height: AppSpacing.md),
              Center(child: InitialsAvatar(name: latest.displayName, size: 88)),
              const SizedBox(height: AppSpacing.md),
              Center(child: Text(latest.displayName, key: const Key('call-number-name'), style: theme.textTheme.headlineSmall)),
              if (latest.formattedNumber != null)
                Center(child: Text(latest.formattedNumber!, key: const Key('call-number-number'), style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textDim))),
              const SizedBox(height: AppSpacing.md),
              if (latest.lead case final lead?)
                Center(
                  child: TextButton.icon(
                    key: const Key('call-number-view-lead'),
                    icon: const Icon(Icons.person_search_outlined, size: 18),
                    label: const Text('View lead'),
                    onPressed: () => context.push(RoutePaths.leadDetail(lead.id)),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: Text('Call logs', style: theme.textTheme.titleMedium)),
                  TextButton(
                    key: const Key('call-number-view-all'),
                    onPressed: () => context.push(RoutePaths.callsForNumber(phone)),
                    child: Text(state.total > 1 ? 'View all (${state.total})' : 'View all'),
                  ),
                ],
              ),
              Card(
                margin: EdgeInsets.zero,
                child: CallTile(call: latest, showLeadName: false, recording: recordings[latest.id], showInfo: false),
              ),
            ],
          ),
      },
    );
  }
}
