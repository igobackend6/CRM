import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/auth/domain/entities/auth_state.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:mobile/services/api/me_api_data_source.dart';

import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import 'fake_auth_repository.dart';

void main() {
  group('AuthController', () {
    test('no existing session -> unauthenticated', () async {
      final repo = FakeAuthRepository();
      final controller = AuthController(repo, FakeMeApiDataSource());

      await waitUntil(() => controller.state.status != AuthStatus.initializing);

      expect(controller.state.status, AuthStatus.unauthenticated);
      controller.dispose();
      repo.dispose();
    });

    test('existing session detected on startup -> authenticated with profile', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', phone: '+919876543210');
      final controller = AuthController(repo, FakeMeApiDataSource());

      await waitUntil(() => controller.state.status == AuthStatus.authenticated);

      expect(controller.state.user!.id, 'u1');
      expect(controller.state.user!.phone, '+919876543210');
      controller.dispose();
      repo.dispose();
    });

    test('sign-in success -> authenticated', () async {
      final repo = FakeAuthRepository();
      final controller = AuthController(repo, FakeMeApiDataSource());
      await waitUntil(() => controller.state.status == AuthStatus.unauthenticated);

      await controller.signIn(phone: '+919876543210', password: 'secret');

      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.state.user!.phone, '+919876543210');
      controller.dispose();
      repo.dispose();
    });

    test('sign-in failure -> error state with message', () async {
      final repo = FakeAuthRepository()..signInError = const AuthException('Invalid login credentials.');
      final controller = AuthController(repo, FakeMeApiDataSource());
      await waitUntil(() => controller.state.status == AuthStatus.unauthenticated);

      await controller.signIn(phone: '+919876543210', password: 'wrong');

      expect(controller.state.status, AuthStatus.error);
      expect(controller.state.errorMessage, 'Invalid login credentials.');
      controller.dispose();
      repo.dispose();
    });

    test('sign-out -> unauthenticated and repository.signOut called', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', phone: '+919876543210');
      final controller = AuthController(repo, FakeMeApiDataSource());
      await waitUntil(() => controller.state.status == AuthStatus.authenticated);

      await controller.signOut();

      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(repo.signOutCalled, isTrue);
      controller.dispose();
      repo.dispose();
    });

    test('profile not found -> error state (does not crash)', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', phone: '+919876543210')
        ..profileError = const AuthException('No profile found for this account.');
      final controller = AuthController(repo, FakeMeApiDataSource());

      await waitUntil(() => controller.state.status == AuthStatus.error);

      expect(controller.state.errorMessage, contains('No profile found'));
      controller.dispose();
      repo.dispose();
    });

    test('backend 401 on /me forces sign-out and surfaces an error', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', phone: '+919876543210');
      final controller = AuthController(repo, FakeMeApiDataSource()..result = const BackendMeUnauthorized());

      await waitUntil(() => controller.state.status == AuthStatus.error);

      expect(repo.signOutCalled, isTrue);
      controller.dispose();
      repo.dispose();
    });

    test('backend 403 on /me surfaces an access-problem error', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', phone: '+919876543210');
      final controller = AuthController(repo, FakeMeApiDataSource()..result = const BackendMeForbidden());

      await waitUntil(() => controller.state.status == AuthStatus.error);

      expect(controller.state.errorMessage, contains('access'));
      controller.dispose();
      repo.dispose();
    });

    test('backend network error on /me is non-fatal — still authenticates', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', phone: '+919876543210');
      final controller = AuthController(
        repo,
        FakeMeApiDataSource()..result = const BackendMeNetworkError('timeout'),
      );

      await waitUntil(() => controller.state.status == AuthStatus.authenticated);

      controller.dispose();
      repo.dispose();
    });

    test('session with must_change_password -> mustChangePassword state, no profile/backend call', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(
          userId: 'u1',
          accessToken: 't1',
          phone: '+919876543210',
          mustChangePassword: true,
        );
      final meApi = FakeMeApiDataSource();
      final controller = AuthController(repo, meApi);

      await waitUntil(() => controller.state.status == AuthStatus.mustChangePassword);

      expect(controller.state.user, isNull);
      expect(meApi.callCount, 0);
      controller.dispose();
      repo.dispose();
    });

    test('sign-in with must_change_password flag -> mustChangePassword, not authenticated', () async {
      final repo = FakeAuthRepository();
      final controller = AuthController(repo, FakeMeApiDataSource());
      await waitUntil(() => controller.state.status == AuthStatus.unauthenticated);

      repo.signInWithPhonePasswordOverride = () => const SessionInfo(
            userId: 'u1',
            accessToken: 't1',
            phone: '+919876543210',
            mustChangePassword: true,
          );
      await controller.signIn(phone: '+919876543210', password: 'temp-pass');

      expect(controller.state.status, AuthStatus.mustChangePassword);
      controller.dispose();
      repo.dispose();
    });

    test('changePassword success -> re-establishes session as authenticated', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(
          userId: 'u1',
          accessToken: 't1',
          phone: '+919876543210',
          mustChangePassword: true,
        );
      final controller = AuthController(repo, FakeMeApiDataSource());
      await waitUntil(() => controller.state.status == AuthStatus.mustChangePassword);

      await controller.changePassword('new-strong-password');

      expect(repo.updatePasswordCalled, isTrue);
      expect(controller.state.status, AuthStatus.authenticated);
      controller.dispose();
      repo.dispose();
    });

    test('changePassword failure throws and leaves state at mustChangePassword', () async {
      final repo = FakeAuthRepository()
        ..session = const SessionInfo(
          userId: 'u1',
          accessToken: 't1',
          phone: '+919876543210',
          mustChangePassword: true,
        )
        ..updatePasswordError = const AuthException('Password is too weak.');
      final controller = AuthController(repo, FakeMeApiDataSource());
      await waitUntil(() => controller.state.status == AuthStatus.mustChangePassword);

      await expectLater(controller.changePassword('weak'), throwsA(isA<AuthException>()));

      expect(controller.state.status, AuthStatus.mustChangePassword);
      controller.dispose();
      repo.dispose();
    });
  });
}
