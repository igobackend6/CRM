import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../call_sync/domain/call_recording.dart';
import '../../../call_sync/presentation/providers/call_sync_providers.dart';
import '../../../call_sync/presentation/widgets/call_recording_play_button.dart';
import '../../domain/entities/call.dart';
import '../../domain/entities/call_list_state.dart';
import '../controllers/call_list_controller.dart';
import '../providers/call_providers.dart';

String formatCallDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

/// Call Log (Phase 9 §2) — workspace-scoped, loading/empty/error,
/// pull-to-refresh, load-more pagination. Mirrors FollowUpListScreen's
/// structure. No search box or FAB here: creation is lead-scoped (§4 —
/// there is no lead picker this phase), reached from a lead's own Calls
/// section instead. Optionally scoped to one lead (`leadId`) — Lead
/// Detail's "View all calls" (§6) pushes this screen with a leadId
/// rather than opening a second list implementation.
class CallListScreen extends ConsumerStatefulWidget {
  const CallListScreen({super.key, this.leadId, this.phone});

  final String? leadId;

  /// The last 10 digits of a number: only calls to/from it (a number's "Call logs" page).
  final String? phone;

  @override
  ConsumerState<CallListScreen> createState() => _CallListScreenState();
}

class _CallListScreenState extends ConsumerState<CallListScreen> {
  final _scrollController = ScrollController();
  CallFilter _filter = CallFilter.all;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _notifier.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  CallListController get _notifier => widget.phone != null
      ? ref.read(phoneCallListControllerProvider(widget.phone!).notifier)
      : widget.leadId == null
          ? ref.read(callListControllerProvider.notifier)
          : ref.read(leadCallListControllerProvider(widget.leadId!).notifier);

  @override
  Widget build(BuildContext context) {
    final state = widget.phone != null
        ? ref.watch(phoneCallListControllerProvider(widget.phone!))
        : widget.leadId == null
            ? ref.watch(callListControllerProvider)
            : ref.watch(leadCallListControllerProvider(widget.leadId!));

    return Scaffold(
      appBar: brandAppBar(title: Text(widget.phone != null ? 'Call logs' : 'Calls')),
      body: Column(
        children: [
          _FilterBar(
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(CallListState state) {
    switch (state.status) {
      case CallListStatus.initial:
      case CallListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case CallListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load calls.',
          onRetry: () => _notifier.refresh(),
        );

      case CallListStatus.empty:
        return RefreshIndicator(
          onRefresh: () => _notifier.refresh(),
          child: ListView(
            children: const [
              SizedBox(height: 80),
              EmptyStateView(icon: Icons.call_outlined, message: 'No calls logged yet.'),
            ],
          ),
        );

      case CallListStatus.success:
      case CallListStatus.refreshing:
      case CallListStatus.loadingMore:
        final items = [for (final c in state.items) if (_filter.matches(c)) c];
        final recordings = ref.watch(callRecordingsProvider(state.items.map((c) => c.id).take(100).join(','))).valueOrNull ?? const {};
        if (items.isEmpty && !state.hasMore) {
          return ListView(
            children: [
              const SizedBox(height: 80),
              EmptyStateView(key: const Key('call-filter-empty'), icon: _filter.icon, message: 'No ${_filter.label.toLowerCase()} yet.'),
            ],
          );
        }
        return RefreshIndicator(
          onRefresh: () => _notifier.refresh(),
          child: ListView.separated(
            controller: _scrollController,
            itemCount: items.length + (state.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index >= items.length) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final call = items[index];
              return CallTile(
                call: call,
                showLeadName: widget.leadId == null,
                recording: recordings[call.id],
                // Already on this number's own call logs: its info icon would open the page we came from.
                showInfo: widget.phone == null,
              );
            },
          ),
        );
    }
  }
}

/// Shared by the global call log, Lead Detail's Calls section, and
/// Customer 360's Calls section — one tile widget, not three copies.
/// Calls synced from the phone can be missed / unanswered / declined; say so on the tile.
String? _unansweredLabel(Call call) => switch (call.state) {
      'MISSED' => 'Missed',
      'CANCELLED' => call.isInbound ? 'Declined' : 'Not answered',
      'FAILED' => 'Failed',
      _ => null,
    };

/// The filter tabs on the Calls screen (the same set Callyzer has). Calls synced from the phone
/// carry a direction and a state, which is all these need.
enum CallFilter {
  all('All Calls', Icons.phone),
  incoming('Incoming', Icons.call_received),
  outgoing('Outgoing', Icons.call_made),
  missed('Missed', Icons.phone_missed),
  rejected('Rejected', Icons.phone_disabled),
  neverAttended('Never Attended', Icons.phone_callback),
  notPickedUp('Not Pickup by Client', Icons.phone_forwarded);

  const CallFilter(this.label, this.icon);

  final String label;
  final IconData icon;

  bool matches(Call call) => switch (this) {
        CallFilter.all => true,
        CallFilter.incoming => call.isInbound,
        CallFilter.outgoing => !call.isInbound,
        // Missed: an incoming call nobody picked up (or that rang out).
        CallFilter.missed => call.isInbound && call.state == 'MISSED',
        // Rejected: an incoming call that was declined.
        CallFilter.rejected => call.isInbound && call.state == 'CANCELLED',
        // Never attended: every incoming call that went unanswered, either way.
        CallFilter.neverAttended => call.isInbound && (call.state == 'MISSED' || call.state == 'CANCELLED'),
        // Not picked up by the client: an outgoing call that went unanswered.
        CallFilter.notPickedUp => !call.isInbound && call.state == 'CANCELLED',
      };
}

class CallTile extends StatelessWidget {
  const CallTile({super.key, required this.call, this.showLeadName = true, this.recording, this.showInfo = true});

  final Call call;
  final bool showLeadName;

  /// The (i) icon that opens the number's page. Hidden on lead-scoped lists and a number's own list.
  final bool showInfo;

  /// The call's recording, when it has one: a play button is shown.
  final CallRecording? recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Like the phone's own call log: a call nobody picked up (incoming) is red.
    final missed = call.isMissedIncoming;
    final accent = missed ? theme.colorScheme.error : theme.colorScheme.secondary;
    final number = showLeadName ? call.formattedNumber : null;
    final phoneKey = call.phoneKey;
    return InkWell(
      onTap: () => context.push(RoutePaths.callDetail(call.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  child: Icon(call.isInbound ? Icons.call_received : Icons.call_made, size: 16, color: accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showLeadName ? call.displayName : (call.isInbound ? 'Incoming' : 'Outgoing'),
                        key: Key('call-name-${call.id}'),
                        style: theme.textTheme.titleMedium?.copyWith(color: missed ? accent : null),
                      ),
                      // The number under the name, as the phone's own log shows it (not repeated when the
                      // name is the number itself).
                      if (number != null && number != call.displayName)
                        Text(number, key: Key('call-number-${call.id}'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim)),
                    ],
                  ),
                ),
                if (call.outcome != null)
                  AppStatusChip.forCallOutcome(name: call.outcome!.name, isPositive: call.outcome!.isPositive)
                else if (_unansweredLabel(call) case final label?)
                  AppStatusChip(label: label, tone: ChipTone.warning),
                if (recording != null) CallRecordingPlayButton(recording: recording!),
                if (showInfo && phoneKey != null)
                  IconButton(
                    key: Key('call-info-${call.id}'),
                    tooltip: 'Call logs for this number',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => context.push(RoutePaths.callNumber(phoneKey)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.schedule_outlined, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(formatCallDateTime(call.startedAt), style: theme.textTheme.bodySmall),
                const SizedBox(width: AppSpacing.md),
                Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(call.formattedDuration, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(call.agentMember?.fullName ?? 'Unknown', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The scrolling row of filter tabs under the app bar (All Calls, Incoming, Outgoing, Missed, ...).
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final CallFilter selected;
  final ValueChanged<CallFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    // A short, fixed set: build every tab (no lazy list) so each is always findable and focusable.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          for (final filter in CallFilter.values) ...[
            ChoiceChip(
              key: Key('call-filter-${filter.name}'),
              avatar: Icon(filter.icon, size: 16),
              label: Text(filter.label),
              selected: filter == selected,
              onSelected: (_) => onSelected(filter),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
