import 'package:mobile/features/onboarding/data/onboarding_storage.dart';

class FakeOnboardingStorage implements OnboardingStorage {
  FakeOnboardingStorage({this.seen = false, this.failRead = false, this.failWrite = false});

  bool seen;
  final bool failRead;
  final bool failWrite;

  @override
  Future<bool> isSeen() async {
    if (failRead) throw Exception('read failed');
    return seen;
  }

  @override
  Future<void> markSeen() async {
    if (failWrite) throw Exception('write failed');
    seen = true;
  }
}
