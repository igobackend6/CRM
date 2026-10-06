import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/onboarding_storage.dart';
import '../../domain/onboarding_status.dart';

class OnboardingController extends StateNotifier<OnboardingStatus> {
  OnboardingController(this._storage) : super(OnboardingStatus.loading) {
    _load();
  }

  final OnboardingStorage _storage;
  bool _completed = false;

  Future<void> _load() async {
    OnboardingStatus next;
    try {
      next = await _storage.isSeen() ? OnboardingStatus.seen : OnboardingStatus.unseen;
    } catch (e, st) {
      // Unreadable storage must never lock the user out: showing the
      // slides once more is harmless, an endless splash is not.
      AppLogger.warning('Could not read onboarding flag: $e');
      AppLogger.debug('$st');
      next = OnboardingStatus.unseen;
    }
    // A "Get Started" tap that beat the storage read must not be undone.
    if (mounted && !_completed) state = next;
  }

  /// "Get Started" / "Skip". Flips the in-memory state first so the router
  /// moves on to login immediately; a failed write only means the slides
  /// show once more next launch.
  Future<void> complete() async {
    _completed = true;
    state = OnboardingStatus.seen;
    try {
      await _storage.markSeen();
    } catch (e) {
      AppLogger.warning('Could not save onboarding flag: $e');
    }
  }
}
