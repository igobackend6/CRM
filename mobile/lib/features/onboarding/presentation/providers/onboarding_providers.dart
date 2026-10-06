import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/onboarding_storage.dart';
import '../../domain/onboarding_status.dart';
import '../controllers/onboarding_controller.dart';

final onboardingStorageProvider = Provider<OnboardingStorage>((ref) => SecureOnboardingStorage());

final onboardingControllerProvider = StateNotifierProvider<OnboardingController, OnboardingStatus>(
  (ref) => OnboardingController(ref.watch(onboardingStorageProvider)),
);
