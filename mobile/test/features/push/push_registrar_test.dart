import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/domain/entities/app_user.dart';
import 'package:mobile/features/auth/domain/entities/auth_state.dart';
import 'package:mobile/features/auth/domain/entities/profile.dart';
import 'package:mobile/features/push/domain/fcm_token_source.dart';
import 'package:mobile/features/push/domain/repositories/push_repository.dart';
import 'package:mobile/features/push/presentation/push_registrar.dart';

class _FakeTokenSource implements FcmTokenSource {
  _FakeTokenSource(this.token);
  String? token;
  final _refresh = StreamController<String>.broadcast();
  bool deleted = false;

  void emitRefresh(String t) => _refresh.add(t);

  @override
  Future<String?> getToken() async => token;
  @override
  Stream<String> get onTokenRefresh => _refresh.stream;
  @override
  Future<void> deleteToken() async => deleted = true;
}

class _FakePushRepo implements PushRepository {
  final registered = <String>[];
  final deregistered = <String>[];

  @override
  Future<void> registerToken({required String accessToken, required String token, required String platform}) async =>
      registered.add(token);
  @override
  Future<void> deregisterToken({required String accessToken, required String token}) async => deregistered.add(token);
}

const _user = AppUser(
  id: 'u1',
  phone: '+919876543210',
  accessToken: 'tok-1',
  profile: Profile(id: 'u1', fullName: 'Rep'),
);
final _authed = AuthState.authenticated(_user);
const _out = AuthState.unauthenticated();

void main() {
  late StreamController<AuthState> auth;
  late _FakeTokenSource source;
  late _FakePushRepo repo;
  PushRegistrar? registrar;

  setUp(() {
    auth = StreamController<AuthState>.broadcast();
    source = _FakeTokenSource('fcm-123');
    repo = _FakePushRepo();
  });
  tearDown(() {
    registrar?.dispose();
    auth.close();
  });

  PushRegistrar build(AuthState initial) => registrar = PushRegistrar(
        initialAuth: initial,
        authChanges: auth.stream,
        source: source,
        repository: repo,
      );

  test('registers the token when the user logs in', () async {
    build(_out);
    auth.add(_authed);
    await Future<void>.delayed(Duration.zero);
    expect(repo.registered, ['fcm-123']);
  });

  test('registers immediately when already authenticated at boot', () async {
    build(_authed);
    await Future<void>.delayed(Duration.zero);
    expect(repo.registered, ['fcm-123']);
  });

  test('deregisters on logout', () async {
    build(_authed);
    await Future<void>.delayed(Duration.zero);
    auth.add(_out);
    await Future<void>.delayed(Duration.zero);
    expect(repo.deregistered, ['fcm-123']);
    expect(source.deleted, isTrue);
  });

  test('no token available is a clean no-op', () async {
    source.token = null;
    build(_out);
    auth.add(_authed);
    await Future<void>.delayed(Duration.zero);
    expect(repo.registered, isEmpty);
  });

  test('a token refresh re-registers the new value', () async {
    build(_authed);
    await Future<void>.delayed(Duration.zero);
    source.token = 'fcm-new';
    source.emitRefresh('fcm-new');
    await Future<void>.delayed(Duration.zero);
    expect(repo.registered, ['fcm-123', 'fcm-new']);
  });

  test('re-registering the same token is skipped', () async {
    build(_authed);
    await Future<void>.delayed(Duration.zero);
    source.emitRefresh('fcm-123'); // same token
    await Future<void>.delayed(Duration.zero);
    expect(repo.registered, ['fcm-123']);
  });
}
