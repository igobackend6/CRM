import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/auth_state.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/settings_providers.dart';

/// How long the app may sit in the background before App Security asks again. Short enough to
/// protect an unattended phone, long enough that a quick trip to the dialer or WhatsApp doesn't
/// nag on every return.
const Duration kAppLockTimeout = Duration(minutes: 1);

/// Pure rule for "should coming back to the app lock it?" — separate so it is unit-testable.
bool shouldLockAfterAbsence({required DateTime? leftAt, required DateTime now, Duration timeout = kAppLockTimeout}) {
  if (leftAt == null) return false;
  return now.difference(leftAt) >= timeout;
}

/// Wraps the whole app (in `MaterialApp.builder`). When App Security is on and someone is signed in,
/// it covers the app with an unlock screen:
///  * when the app starts with a session restored from the last run, and
///  * when the app returns to the foreground after [kAppLockTimeout] or more away.
/// A fresh sign-in never locks (typing the password just proved who it is).
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child, this.clock = DateTime.now});

  final Widget child;

  /// Injectable for tests.
  final DateTime Function() clock;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _authenticating = false;
  bool _sawFreshSignIn = false;
  bool _coldLockPending = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A session that was already signed in before this widget first built (the listeners in build only
    // see later changes) counts as restored from the last run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_signedIn) return;
      _coldLockPending = true;
      _maybeColdLock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _signedIn => ref.read(authControllerProvider).status == AuthStatus.authenticated;

  bool get _lockEnabled => ref.read(appSettingsControllerProvider).appLockEnabled;

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.hidden) {
      // Keep the earliest "left" time; a quick hidden→paused sequence must not reset the clock.
      _leftAt ??= widget.clock();
    } else if (lifecycle == AppLifecycleState.resumed) {
      final leftAt = _leftAt;
      _leftAt = null;
      if (_lockEnabled && _signedIn && shouldLockAfterAbsence(leftAt: leftAt, now: widget.clock())) {
        _lock();
      }
    }
  }

  void _lock() {
    if (_locked) return;
    setState(() => _locked = true);
    _promptSoon();
  }

  void _maybeColdLock() {
    if (!_coldLockPending) return;
    final settings = ref.read(appSettingsControllerProvider);
    if (!settings.loaded || !_signedIn) return;
    _coldLockPending = false;
    if (settings.appLockEnabled) _lock();
  }

  void _promptSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _locked) _unlock();
    });
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final ok = await ref.read(deviceAuthenticatorProvider).authenticate('Unlock ${AppConstants.appName}');
      if (ok && mounted) setState(() => _locked = false);
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthStatus>(authControllerProvider.select((s) => s.status), (previous, next) {
      if (next == AuthStatus.authenticating) _sawFreshSignIn = true;
      if (next == AuthStatus.authenticated && previous != AuthStatus.authenticated) {
        // initializing -> authenticated means a session restored from the last run.
        _coldLockPending = !_sawFreshSignIn;
        _sawFreshSignIn = false;
        _maybeColdLock();
      }
      if (next == AuthStatus.unauthenticated || next == AuthStatus.error) {
        _coldLockPending = false;
        if (_locked) setState(() => _locked = false);
      }
    });
    ref.listen(appSettingsControllerProvider, (previous, next) {
      if (!next.appLockEnabled && _locked) setState(() => _locked = false);
      if (previous?.loaded != true && next.loaded) _maybeColdLock();
    });

    return Stack(
      children: [
        widget.child,
        if (_locked) _LockScreen(onUnlock: _unlock),
      ],
    );
  }

}

class _LockScreen extends ConsumerWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        key: const Key('app-lock-screen'),
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: AppColors.gradientBrand, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: const Icon(Icons.lock_outline, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 20),
                  Text('${AppConstants.appName} is locked', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Confirm it\'s you to continue.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const Key('unlock-button'),
                    onPressed: onUnlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('lock-sign-out'),
                    onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
