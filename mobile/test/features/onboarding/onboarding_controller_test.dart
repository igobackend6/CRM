import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/onboarding/domain/onboarding_status.dart';
import 'package:mobile/features/onboarding/presentation/controllers/onboarding_controller.dart';

import 'fake_onboarding_storage.dart';

void main() {
  group('OnboardingController', () {
    test('starts loading, then unseen on a fresh install', () async {
      final controller = OnboardingController(FakeOnboardingStorage());
      expect(controller.state, OnboardingStatus.loading);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, OnboardingStatus.unseen);
    });

    test('is seen when the flag was saved earlier', () async {
      final controller = OnboardingController(FakeOnboardingStorage(seen: true));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, OnboardingStatus.seen);
    });

    test('unreadable storage falls back to unseen (never blocks the user)', () async {
      final controller = OnboardingController(FakeOnboardingStorage(failRead: true));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, OnboardingStatus.unseen);
    });

    test('complete() persists the flag and moves to seen', () async {
      final storage = FakeOnboardingStorage();
      final controller = OnboardingController(storage);
      await Future<void>.delayed(Duration.zero);

      await controller.complete();

      expect(controller.state, OnboardingStatus.seen);
      expect(storage.seen, isTrue);
    });

    test('complete() before the saved flag finishes loading is not overwritten', () async {
      final controller = OnboardingController(FakeOnboardingStorage());

      await controller.complete(); // the initial read is still in flight
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, OnboardingStatus.seen);
    });

    test('complete() still moves on when saving fails', () async {
      final controller = OnboardingController(FakeOnboardingStorage(failWrite: true));
      await Future<void>.delayed(Duration.zero);

      await controller.complete();

      expect(controller.state, OnboardingStatus.seen);
    });
  });
}
