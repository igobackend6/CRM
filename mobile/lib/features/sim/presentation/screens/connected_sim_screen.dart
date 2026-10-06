import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_retry_view.dart';
import '../../../../core/widgets/app_status_chip.dart';
import '../../../../core/widgets/brand_app_bar.dart';
import '../../domain/sim_card.dart';
import '../../domain/sim_number.dart';
import '../controllers/connected_sim_controller.dart';
import '../providers/sim_providers.dart';

/// Settings > Connected SIM Details: the SIMs in this phone, and which one is the employee's
/// business SIM. Shows only what Android reports.
class ConnectedSimScreen extends ConsumerStatefulWidget {
  const ConnectedSimScreen({super.key});

  @override
  ConsumerState<ConnectedSimScreen> createState() => _ConnectedSimScreenState();
}

class _ConnectedSimScreenState extends ConsumerState<ConnectedSimScreen> with WidgetsBindingObserver {
  // Set once the app actually went to the background (Android Settings, a SIM swap), so the brief
  // pause behind the permission dialog doesn't trigger a re-read.
  bool _wasInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.hidden) {
      _wasInBackground = true;
    } else if (lifecycle == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      ref.read(connectedSimControllerProvider.notifier).onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectedSimControllerProvider);
    final controller = ref.read(connectedSimControllerProvider.notifier);

    ref.listen(connectedSimControllerProvider.select((s) => s.notice), (_, notice) {
      if (notice == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
      controller.clearNotice();
    });
    // Keep Settings' "Connected SIM Details" value in step with the choice made here. Keyed on the
    // selection object, not its id: the instant (optimistic) update and the saved one share an id,
    // and only a reload after the save sees the new choice in storage.
    ref.listen(connectedSimControllerProvider.select((s) => s.selection), (_, _) {
      ref.invalidate(businessSimSelectionProvider);
    });

    return Scaffold(
      appBar: brandAppBar(title: const Text('Connected SIM Details')),
      body: switch (state.status) {
        ConnectedSimStatus.loading => const _Detecting(),
        ConnectedSimStatus.ready => _SimList(state: state, controller: controller),
        ConnectedSimStatus.permissionRequired => _PermissionView(
            permanentlyDenied: false,
            busy: state.requestingPermission,
            onPressed: controller.requestPermission,
          ),
        ConnectedSimStatus.permissionPermanentlyDenied => _PermissionView(
            permanentlyDenied: true,
            busy: false,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final opened = await controller.openAppSettings();
              if (!opened) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Open your phone\'s Settings > Apps > Sales CRM > Permissions and allow Phone.')),
                );
              }
            },
          ),
        ConnectedSimStatus.unavailable => const _Message(
            key: Key('sim-unavailable'),
            icon: Icons.sim_card_alert_outlined,
            title: 'SIM details aren\'t available on this device.',
            body: 'This phone doesn\'t report SIM cards to apps, so a business SIM can\'t be chosen here.',
          ),
        ConnectedSimStatus.error => AppRetryView(
            key: const Key('sim-error'),
            message: ConnectedSimController.readFailedMessage,
            onRetry: controller.load,
          ),
      },
    );
  }
}

class _Detecting extends StatelessWidget {
  const _Detecting();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('sim-loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: AppSpacing.md),
          Text('Detecting SIM cards...'),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.title, required this.body, this.action, this.inList = false});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  /// Already inside a scrolling list (so no scroll view of its own).
  final bool inList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: AppSpacing.md),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim)),
          if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
        ],
      ),
    );
    return inList ? content : Center(child: SingleChildScrollView(child: content));
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.permanentlyDenied, required this.busy, required this.onPressed});

  final bool permanentlyDenied;
  final bool busy;
  final VoidCallback onPressed;

  static const _why = 'Sales CRM reads which SIM cards are in this phone so you can choose the one you use for '
      'business calls. It doesn\'t read your calls, messages or contacts, and your SIM details stay on this phone.';

  @override
  Widget build(BuildContext context) {
    return _Message(
      key: Key(permanentlyDenied ? 'sim-permission-permanently-denied' : 'sim-permission-required'),
      icon: Icons.sim_card_outlined,
      title: 'Phone permission is required to detect SIM details.',
      body: permanentlyDenied
          ? '$_why\n\nPhone access is turned off for Sales CRM. Open its app settings, tap Permissions > Phone and allow it, then come back.'
          : _why,
      action: FilledButton.icon(
        key: Key(permanentlyDenied ? 'sim-open-settings' : 'sim-allow-permission'),
        onPressed: busy ? null : onPressed,
        icon: Icon(permanentlyDenied ? Icons.settings_outlined : Icons.check),
        label: Text(permanentlyDenied ? 'Open app settings' : 'Allow phone access'),
      ),
    );
  }
}

class _SimList extends StatelessWidget {
  const _SimList({required this.state, required this.controller});

  final ConnectedSimState state;
  final ConnectedSimController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = state.selection;
    final selected = state.selectedSim;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (state.selectionUnavailable) ...[
            _UnavailableBanner(previous: selection!.summary),
            const SizedBox(height: AppSpacing.md),
          ],
          if (state.sims.isEmpty)
            const _Message(
              key: Key('sim-none'),
              icon: Icons.sim_card_alert_outlined,
              title: 'No active SIM detected.',
              body: 'No active SIM card was detected. Insert a SIM card (or turn one on in your phone\'s SIM settings), then tap Refresh.',
              inList: true,
            )
          else ...[
            Text('Connected SIM', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Enter and submit each SIM\'s mobile number, then select the SIM whose calls should be recorded.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final sim in state.sims) ...[
              _SimCardTile(
                sim: sim,
                selected: selected?.subscriptionId == sim.subscriptionId,
                savedNumber: state.numbers[sim.subscriptionId],
                onSelect: () => controller.select(sim),
                onSubmitNumber: (raw) => controller.submitNumber(sim, raw),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(
            key: const Key('sim-selected-summary'),
            label: 'Record calls from',
            value: selected != null ? _withNumber(selection!.summary, state.numberFor(selected)) : 'None selected',
          ),
          if (state.lastDetectedAt != null)
            _SummaryRow(
              key: const Key('sim-last-detected'),
              label: 'Last detected',
              value: formatDetectedAt(context, state.lastDetectedAt!, DateTime.now()),
            ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            key: const Key('sim-refresh'),
            onPressed: state.refreshing ? null : controller.refresh,
            icon: state.refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text('Refresh SIM Details'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Read from this phone and kept on it. Call recording for the selected SIM is coming soon; '
            'recordings will be stored on this phone.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textDim),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String _withNumber(String summary, String? number) => number == null ? summary : '$summary ($number)';

/// "Today, 10:30 AM" /"Yesterday, 9:05 PM" / "28 Sep 2026, 6:00 PM", in the phone's locale.
String formatDetectedAt(BuildContext context, DateTime at, DateTime now) {
  final l10n = MaterialLocalizations.of(context);
  final time = l10n.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  return '${l10n.formatMediumDate(at)}, $time';
}

class _UnavailableBanner extends StatelessWidget {
  const _UnavailableBanner({required this.previous});

  final String previous;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('sim-selection-unavailable'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Selected SIM unavailable', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text('The previously selected SIM ($previous) is no longer available. Select one of the SIMs in this phone.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimCardTile extends StatelessWidget {
  const _SimCardTile({
    required this.sim,
    required this.selected,
    required this.savedNumber,
    required this.onSelect,
    required this.onSubmitNumber,
  });

  final SimCard sim;
  final bool selected;
  final String? savedNumber;
  final VoidCallback onSelect;
  final Future<String?> Function(String raw) onSubmitNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dim = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim);
    final operator = sim.operatorName;
    final showDisplayName = sim.displayName != null && sim.displayName != operator;

    return Material(
      key: Key('sim-card-${sim.subscriptionId}'),
      color: selected ? primary.withValues(alpha: 0.06) : theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        side: BorderSide(color: selected ? primary : theme.colorScheme.outline, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sim_card_outlined, color: selected ? primary : theme.colorScheme.outline),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sim.simLabel, style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.xs),
                        Text(operator ?? 'Carrier unavailable', style: operator == null ? dim : theme.textTheme.bodyLarge),
                        if (showDisplayName) Text(sim.displayName!, style: dim),
                        Text(sim.slotLabel ?? 'Slot unavailable', style: dim),
                        if (sim.stateProblem != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          AppStatusChip(label: sim.stateProblem!, tone: ChipTone.warning),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Semantics(
                    selected: selected,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          size: 20,
                          color: selected ? primary : AppColors.textDim,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          selected ? 'Selected' : 'Select',
                          style: TextStyle(fontWeight: FontWeight.w600, color: selected ? primary : AppColors.textDim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Full card width, so the number has room to be read and typed.
              _SimNumberField(
                key: ValueKey('sim-number-field-${sim.subscriptionId}'),
                subscriptionId: sim.subscriptionId,
                savedNumber: savedNumber,
                detectedNumber: sim.phoneNumber,
                onSubmit: onSubmitNumber,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The SIM's mobile number, typed by the employee (prefilled with Android's number when it has
/// one) and saved with Submit.
class _SimNumberField extends StatefulWidget {
  const _SimNumberField({
    super.key,
    required this.subscriptionId,
    required this.savedNumber,
    required this.detectedNumber,
    required this.onSubmit,
  });

  final int subscriptionId;
  final String? savedNumber;
  final String? detectedNumber;
  final Future<String?> Function(String raw) onSubmit;

  @override
  State<_SimNumberField> createState() => _SimNumberFieldState();
}

class _SimNumberFieldState extends State<_SimNumberField> {
  late final TextEditingController _text = TextEditingController(text: widget.savedNumber ?? widget.detectedNumber ?? '');
  String? _error;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _SimNumberField old) {
    super.didUpdateWidget(old);
    // The saved numbers arrive after the first frame; fill the field unless the employee typed.
    if (old.savedNumber == null && widget.savedNumber != null && _text.text == (old.detectedNumber ?? '')) {
      _text.text = widget.savedNumber!;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSubmit(_text.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.subscriptionId;
    final saved = widget.savedNumber != null && _error == null && normalizeSimNumber(_text.text) == widget.savedNumber;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: Key('sim-number-$id'),
            controller: _text,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]'))],
            onSubmitted: (_) => _submit(),
            // Rebuild so "Saved" disappears as soon as the number is edited.
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Mobile number',
              hintText: '10-digit mobile number',
              errorText: _error,
              helperText: saved
                  ? 'Saved'
                  : widget.detectedNumber != null
                      ? 'Detected from the SIM. Tap Submit to confirm.'
                      : 'Phone number unavailable from the SIM. Enter it.',
              helperMaxLines: 2,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: FilledButton(
            key: Key('sim-number-submit-$id'),
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44), padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md)),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit'),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text('$label:', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
