import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/auth_state.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/entities/activity_summary.dart';
import '../../domain/repositories/activity_repository.dart';

int _deviceUtcOffsetMinutes() => DateTime.now().timeZoneOffset.inMinutes;

Timer _periodicTimer(Duration interval, void Function() onTick) => Timer.periodic(interval, (_) => onTick());

/// App-lifetime tracker behind Login Analytics. While a user is signed in
/// with a workspace selected it checks in with the backend once a minute,
/// which is what "logged in" means: the app process being alive, in the
/// foreground OR the background. (Time the app is closed or killed simply
/// produces no heartbeats, and the backend ends the session where they
/// stopped, so that gap is never counted.)
///
/// It also owns the break toggle, and its state is whether the member is on
/// a break — refreshed by every heartbeat and break action.
///
/// Sign-out happens in four different places in the app, so instead of
/// hooking each one this watches the auth state: when the session goes
/// away it sends the final "sign-out" itself, with the last credentials it
/// saw (best effort — if it cannot, the backend closes the session at the
/// last heartbeat anyway, at most a minute short).
class ActivityController extends StateNotifier<ActivityStatus> with WidgetsBindingObserver {
  ActivityController(
    this._repository,
    this._ref, {
    this.interval = const Duration(minutes: 1),
    int Function()? utcOffsetMinutes,
    Timer Function(Duration interval, void Function() onTick)? startTimer,
  })  : _utcOffsetMinutes = utcOffsetMinutes ?? _deviceUtcOffsetMinutes,
        _startTimer = startTimer ?? _periodicTimer,
        super(ActivityStatus.off) {
    WidgetsBinding.instance.addObserver(this);
    _ref.listen<AuthState>(authControllerProvider, (previous, next) => _evaluate());
    _ref.listen<WorkspaceState>(workspaceControllerProvider, (previous, next) => _evaluate());
    _evaluate();
  }

  final ActivityRepository _repository;
  final Ref _ref;
  final Duration interval;
  final int Function() _utcOffsetMinutes;
  final Timer Function(Duration interval, void Function() onTick) _startTimer;

  Timer? _timer;
  bool _running = false;
  LeadRequestContext? _lastContext;

  bool get isTracking => _running;

  /// Starts or stops the heartbeat loop to match whether there is a
  /// signed-in user with a selected workspace. Called on every auth or
  /// workspace change, so it also refreshes the token a refresh replaced.
  void _evaluate() {
    final context = resolveLeadContext(_ref.read);
    if (context != null) {
      _lastContext = context;
      if (!_running) {
        _running = true;
        _beat();
        _timer = _startTimer(interval, _beat);
      }
      return;
    }
    if (_running) {
      _running = false;
      _timer?.cancel();
      _timer = null;
      final last = _lastContext;
      _lastContext = null;
      if (mounted) state = ActivityStatus.off;
      if (last != null) unawaited(_sendSignOut(last));
    }
  }

  Future<void> _beat() async {
    final context = resolveLeadContext(_ref.read) ?? _lastContext;
    if (context == null) return;
    try {
      final status = await _repository.heartbeat(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        utcOffsetMinutes: _utcOffsetMinutes(),
      );
      if (mounted && _running) state = status;
    } catch (e) {
      // A missed heartbeat is not user-visible: the next one carries on,
      // and the backend tolerates a few before it ends the session.
      AppLogger.warning('Activity heartbeat failed: $e');
    }
  }

  Future<void> _sendSignOut(LeadRequestContext context) async {
    try {
      await _repository.signOut(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        utcOffsetMinutes: _utcOffsetMinutes(),
      );
    } catch (e) {
      AppLogger.warning('Activity sign-out report failed (the backend will end the session itself): $e');
    }
  }

  /// A heartbeat the moment the app goes to the background or comes back,
  /// so the session's last-seen time is fresh at exactly those edges.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (!_running) return;
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.resumed) {
      _beat();
    }
  }

  /// Throws the API's `AppException` on failure so the caller can tell the
  /// user the break did not start.
  Future<void> startBreak() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    state = await _repository.startBreak(
      accessToken: context.accessToken,
      workspaceId: context.workspaceId,
      utcOffsetMinutes: _utcOffsetMinutes(),
    );
  }

  Future<void> endBreak() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;
    state = await _repository.endBreak(
      accessToken: context.accessToken,
      workspaceId: context.workspaceId,
      utcOffsetMinutes: _utcOffsetMinutes(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
