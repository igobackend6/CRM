import 'dart:async';

import 'package:mobile/features/auth/domain/entities/profile.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/domain/repositories/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  SessionInfo? session;
  Profile? profileToReturn;
  Object? profileError;
  Object? signInError;
  Object? updatePasswordError;
  bool signOutCalled = false;
  bool updatePasswordCalled = false;

  /// Lets a test control the exact `SessionInfo` a successful sign-in
  /// produces (e.g. one carrying `mustChangePassword: true`) instead of
  /// the default synthesized below.
  SessionInfo Function()? signInWithPhonePasswordOverride;

  final _controller = StreamController<void>.broadcast();

  @override
  SessionInfo? readCurrentSession() => session;

  /// What a successful refresh of an expired session leaves behind (null = nothing to refresh).
  SessionInfo? sessionAfterRefresh;
  bool refreshEndsSession = false;
  int refreshCalls = 0;

  @override
  Future<void> refreshIfExpired() async {
    refreshCalls++;
    if (refreshEndsSession) {
      session = null;
    } else if (sessionAfterRefresh != null) {
      session = sessionAfterRefresh;
      sessionAfterRefresh = null;
    }
  }

  @override
  Stream<void> get authStateChanges => _controller.stream;

  @override
  Future<Profile> loadProfile(String userId) async {
    if (profileError != null) throw profileError!;
    return profileToReturn ?? Profile(id: userId, fullName: 'Test User');
  }

  @override
  Future<void> signInWithPhonePassword({required String phone, required String password}) async {
    if (signInError != null) throw signInError!;
    session = signInWithPhonePasswordOverride?.call() ??
        SessionInfo(userId: 'user-1', accessToken: 'token-1', phone: phone);
    _controller.add(null);
  }

  @override
  Future<void> signInWithEmailPassword({required String email, required String password}) async {
    if (signInError != null) throw signInError!;
    session = signInWithPhonePasswordOverride?.call() ??
        SessionInfo(userId: 'user-1', accessToken: 'token-1', phone: '+919876543210');
    _controller.add(null);
  }

  @override
  Future<void> updatePassword({required String newPassword}) async {
    updatePasswordCalled = true;
    if (updatePasswordError != null) throw updatePasswordError!;
    final current = session;
    if (current != null) {
      session = SessionInfo(userId: current.userId, accessToken: current.accessToken, phone: current.phone);
    }
    _controller.add(null);
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    session = null;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}
