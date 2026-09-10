import 'dart:async';

import 'package:mobile/features/auth/domain/entities/profile.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/domain/repositories/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  SessionInfo? session;
  Profile? profileToReturn;
  Object? profileError;
  Object? signInError;
  bool signOutCalled = false;

  final _controller = StreamController<void>.broadcast();

  @override
  SessionInfo? readCurrentSession() => session;

  @override
  Stream<void> get authStateChanges => _controller.stream;

  @override
  Future<Profile> loadProfile(String userId) async {
    if (profileError != null) throw profileError!;
    return profileToReturn ?? Profile(id: userId, fullName: 'Test User');
  }

  @override
  Future<void> signInWithEmailPassword({required String email, required String password}) async {
    if (signInError != null) throw signInError!;
    session = SessionInfo(userId: 'user-1', accessToken: 'token-1', email: email);
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
