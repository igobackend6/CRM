import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/sim/data/sim_platform_source.dart';
import 'package:mobile/features/sim/data/sim_selection_storage.dart';
import 'package:mobile/features/sim/presentation/providers/sim_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';

/// What the Android bridge would send for one subscription.
Map<String, Object?> simMap(
  int subscriptionId, {
  int? slot,
  String? carrier,
  String? display,
  String? number,
  String? state = 'ready',
}) =>
    {
      'subscriptionId': subscriptionId,
      'slotIndex': slot,
      'carrierName': carrier,
      'displayName': display,
      'phoneNumber': number,
      'simState': state,
      'isActive': true,
    };

class FakeSimPlatformSource implements SimPlatformSource {
  FakeSimPlatformSource({
    this.permission = 'granted',
    this.afterRequest = 'granted',
    List<Map<String, Object?>>? sims,
    this.detectError,
    this.openSettingsResult = true,
  }) : sims = sims ?? [];

  Object? permission;
  Object? afterRequest;
  List<Map<String, Object?>> sims;
  Object? detectError;
  bool openSettingsResult;

  /// When set, detection waits for it — to observe the loading state.
  Completer<void>? detectGate;

  int detectCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<Object?> permissionStatus() async => permission;

  @override
  Future<Object?> requestPermission() async {
    requestCalls++;
    permission = afterRequest;
    return permission;
  }

  @override
  Future<Object?> activeSubscriptions() async {
    detectCalls++;
    if (detectGate != null) await detectGate!.future;
    if (detectError != null) throw detectError!;
    return List<Object?>.from(sims);
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalls++;
    return openSettingsResult;
  }
}

class FakeSimSelectionStorage implements SimSelectionStorage {
  FakeSimSelectionStorage({this.saved, this.failWrite = false, this.failRead = false, this.writeDelay = Duration.zero});

  String? saved;
  bool failWrite;
  bool failRead;

  /// Makes a save take time, like the real encrypted store.
  Duration writeDelay;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (failRead) throw Exception('read failed');
    return saved;
  }

  @override
  Future<void> write(String json) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    if (failWrite) throw Exception('write failed');
    writes++;
    saved = json;
  }
}

/// A signed-in auth repository for [profileId].
FakeAuthRepository signedInAuthRepository([String profileId = 'user-1']) =>
    FakeAuthRepository()..session = SessionInfo(userId: profileId, accessToken: 'token');

/// The overrides the SIM providers need: a signed-in employee, the fake bridge and fake storage.
List<Override> simOverrides({
  required FakeSimPlatformSource source,
  required FakeSimSelectionStorage storage,
  FakeAuthRepository? authRepo,
}) =>
    [
      authRepositoryProvider.overrideWithValue(authRepo ?? signedInAuthRepository()),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      simPlatformSourceProvider.overrideWithValue(source),
      simSelectionStorageProvider.overrideWithValue(storage),
    ];

/// The "Select" / "Selected" label on a SIM card — the spot an employee taps to choose it.
Finder selectLabel(int subscriptionId) =>
    find.descendant(of: find.byKey(Key('sim-card-$subscriptionId')), matching: find.textContaining('Select'));
