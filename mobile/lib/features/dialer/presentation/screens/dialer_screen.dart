import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/dialer_providers.dart';

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
  const DialerScreen({super.key});

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

  void _append(String value) => setState(() => _digits.write(value));

  void _backspace() {
    if (_digits.isEmpty) return;
    final text = _digits.toString();
    setState(() {
      _digits
        ..clear()
        ..write(text.substring(0, text.length - 1));
    });
  }

  Future<void> _call() async {
    final number = _digits.toString();
    if (number.isEmpty) return;
    await ref.read(dialerUrlLauncherProvider).launch(Uri(scheme: 'tel', path: number));
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
                  foregroundColor: AppColors.brandOrange,
                  side: const BorderSide(color: AppColors.brandOrange),
                ),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Create new customer'),
              ),
              const SizedBox(height: AppSpacing.xl),
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
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Backspace',
                      onPressed: _backspace,
                    ),
                ],
              ),
              Container(height: 2, color: AppColors.brandOrange),
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
              const SizedBox(height: AppSpacing.xl),
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
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        onPressed: onPressed,
        shape: const CircleBorder(),
        child: const Icon(Icons.call, size: 30),
      ),
    );
  }
}
