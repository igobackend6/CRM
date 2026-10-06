import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../sim/presentation/providers/sim_providers.dart';
import '../../domain/phone_key.dart';
import '../providers/dialer_providers.dart';
import '../providers/native_dialer_providers.dart';

/// Diameter of one keypad circle. Fixed rather than GridView-derived
/// (which stretched each circle to fill the row, reading as oversized
/// and shadow-smudged against the reference) so the pad reads as
/// compact digits-in-circles with real breathing room around them,
/// same as the reference screenshot.
const _kKeySize = 64.0;

/// The bottom nav's center call FAB destination — a full-screen dialer
/// matching the reference screenshot's own layout: back arrow, a
/// generic contact placeholder, a "Create new customer" shortcut, the
/// typed-number display over an orange underline, a 12-key pad, and a
/// docked call button. No bottom nav bar here, matching the reference
/// (see `RoutePaths.dialer`'s docstring for why it's outside the shell).
///
/// The call button hands off to the device's own phone app via a `tel:`
/// URI (ExternalUrlLauncher, same seam WhatsApp/documents use) — this
/// app has never placed or logged calls itself (see Phase 9's own
/// Calling & Call Log Foundation, a manually-logged history, not a
/// dialer), so that's the honest, real behavior here too.
class DialerScreen extends ConsumerStatefulWidget {
  const DialerScreen({super.key, this.initialNumber});

  /// A number to start with (a tel: link from another app). Never dialled until the member taps Call.
  final String? initialNumber;

  @override
  ConsumerState<DialerScreen> createState() => _DialerScreenState();
}

class _KeyDef {
  const _KeyDef(this.digit, this.letters);
  final String digit;
  final String letters;
}

const _kKeys = [
  _KeyDef('1', ''),
  _KeyDef('2', 'ABC'),
  _KeyDef('3', 'DEF'),
  _KeyDef('4', 'GHI'),
  _KeyDef('5', 'JKL'),
  _KeyDef('6', 'MNO'),
  _KeyDef('7', 'PQRS'),
  _KeyDef('8', 'TUV'),
  _KeyDef('9', 'WXYZ'),
  _KeyDef('*', ''),
  _KeyDef('0', '+'),
  _KeyDef('#', ''),
];

class _DialerScreenState extends ConsumerState<DialerScreen> {
  final _digits = StringBuffer();

  /// The number the CRM lookup is asked about: updated only after a pause in typing.
  String _lookupNumber = '';
  Timer? _lookupTimer;

  @override
  void initState() {
    super.initState();
    final start = widget.initialNumber;
    if (start != null && start.trim().isNotEmpty) {
      _digits.write(start.replaceAll(RegExp(r'[^0-9+*#]'), ''));
      _lookupNumber = _digits.toString();
    }
  }

  @override
  void dispose() {
    _lookupTimer?.cancel();
    super.dispose();
  }

  void _digitsChanged() {
    _lookupTimer?.cancel();
    final number = _digits.toString();
    if (phoneKey(number) == null) {
      _lookupNumber = '';
      return;
    }
    // No server request on every key press: wait for a short pause once 10 digits are typed.
    _lookupTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _lookupNumber = number);
    });
  }

  void _append(String value) {
    setState(() => _digits.write(value));
    _digitsChanged();
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    final text = _digits.toString();
    setState(() {
      _digits
        ..clear()
        ..write(text.substring(0, text.length - 1));
    });
    _digitsChanged();
  }

  void _clearAll() {
    setState(_digits.clear);
    _digitsChanged();
  }

  Future<void> _call() async {
    final number = _digits.toString();
    if (number.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(callPlacerProvider).place(number, fallback: ref.read(dialerUrlLauncherProvider));
    final message = switch (result) {
      CallStartResult.permissionDenied => 'Allow the Phone permission to place calls from Sales CRM.',
      CallStartResult.invalidNumber => 'Enter a valid phone number.',
      CallStartResult.failed => 'Couldn\'t start the call. Try again.',
      _ => null,
    };
    if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = _digits.toString();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              CircleAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.15),
                child: Icon(Icons.person, size: 44, color: theme.colorScheme.outline),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                // go(), not push(): RoutePaths.leadCreate lives inside the
                // bottom-nav shell's Allocations branch (app_router.dart),
                // and the dialer itself sits outside the shell entirely
                // (a plain root-level route). Pushing a shell-branch route
                // on top of a non-shell one makes both the dialer's own
                // route AND the whole shell's branch Navigators (each with
                // their own GlobalKey) coexist mid-transition, which trips
                // Navigator's "!keyReservation.contains(key)" assertion.
                // go() replaces the stack outright instead of layering, so
                // that coexistence never happens.
                onPressed: () => context.go(RoutePaths.leadCreate, extra: number.isEmpty ? null : number),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                ),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Create new customer'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _LeadMatchCard(number: _lookupNumber),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      number,
                      style: theme.textTheme.headlineSmall,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                  if (number.isNotEmpty)
                    Tooltip(
                      message: 'Backspace',
                      child: InkResponse(
                        key: const Key('dialer-backspace'),
                        onTap: _backspace,
                        onLongPress: _clearAll,
                        radius: 24,
                        child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.backspace_outlined)),
                      ),
                    ),
                ],
              ),
              Container(height: 2, color: AppColors.accent),
              const SizedBox(height: AppSpacing.xl),
              for (var row = 0; row < _kKeys.length; row += 3) ...[
                if (row > 0) const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final key in _kKeys.skip(row).take(3))
                      _KeypadButton(keyDef: key, onTap: () => _append(key.digit)),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              const _SimChoice(),
              const SizedBox(height: AppSpacing.md),
              _CallButton(onPressed: _call),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.keyDef, required this.onTap});

  final _KeyDef keyDef;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _kKeySize,
      height: _kKeySize,
      child: Material(
        color: theme.colorScheme.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(keyDef.digit, style: theme.textTheme.titleLarge),
                if (keyDef.letters.isNotEmpty)
                  Text(
                    keyDef.letters,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: FloatingActionButton(
        heroTag: 'dialer-call',
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: onPressed,
        shape: const CircleBorder(),
        child: const Icon(Icons.call, size: 30),
      ),
    );
  }
}

/// Who the typed number is in the CRM: the lead's name, status and a way to open it, or a prompt to
/// create one. Hidden until a full number has been typed.
class _LeadMatchCard extends ConsumerWidget {
  const _LeadMatchCard({required this.number});

  final String number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (number.isEmpty) return const SizedBox(height: 44);
    final theme = Theme.of(context);
    final match = ref.watch(leadMatchProvider(number));
    return match.when(
      loading: () => const SizedBox(height: 44, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
      error: (_, _) => const SizedBox(height: 44),
      data: (lead) => lead == null
          ? SizedBox(
              height: 44,
              child: Center(child: Text('Not in your CRM yet', key: const Key('dialer-no-match'), style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim))),
            )
          : Card(
              key: const Key('dialer-match'),
              margin: EdgeInsets.zero,
              child: ListTile(
                dense: true,
                leading: CircleAvatar(child: Text(lead.name.isEmpty ? '?' : lead.name[0].toUpperCase())),
                title: Text(lead.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([if (lead.isCustomer) 'Customer' else 'Lead', ?lead.status].join(' · ')),
                trailing: TextButton(
                  key: const Key('dialer-match-view'),
                  onPressed: () => context.push(RoutePaths.leadDetail(lead.leadId)),
                  child: const Text('View'),
                ),
              ),
            ),
    );
  }
}

/// Which SIM the call uses, shown only when the CRM is the Phone app and the phone has two SIMs.
class _SimChoice extends ConsumerWidget {
  const _SimChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDefault = ref.watch(defaultDialerControllerProvider.select((s) => s.isDefault));
    final accounts = ref.watch(dialerPhoneAccountsProvider).valueOrNull ?? const [];
    if (!isDefault || accounts.length < 2) return const SizedBox.shrink();
    final business = ref.watch(businessSimSelectionProvider).valueOrNull?.subscriptionId;
    final chosen = ref.watch(dialerSimChoiceProvider) ?? business;
    return Wrap(
      key: const Key('dialer-sim-choice'),
      spacing: AppSpacing.sm,
      alignment: WrapAlignment.center,
      children: [
        for (final a in accounts)
          ChoiceChip(
            key: Key('dialer-sim-${a.subscriptionId ?? a.index}'),
            avatar: const Icon(Icons.sim_card_outlined, size: 16),
            label: Text('SIM ${a.index + 1} · ${a.label}'),
            selected: a.subscriptionId != null ? chosen == a.subscriptionId : false,
            onSelected: a.subscriptionId == null ? null : (_) => ref.read(dialerSimChoiceProvider.notifier).state = a.subscriptionId,
          ),
      ],
    );
  }
}
