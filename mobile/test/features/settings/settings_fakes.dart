import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/utils/location_service.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart' show leadLocationServiceProvider;
import 'package:mobile/features/settings/data/device_authenticator.dart';
import 'package:mobile/features/settings/data/server_ping.dart';
import 'package:mobile/features/settings/data/settings_storage.dart';
import 'package:mobile/features/settings/presentation/providers/diagnostics_providers.dart';
import 'package:mobile/features/settings/presentation/providers/settings_providers.dart';
import 'package:mobile/features/sim/presentation/providers/sim_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../call_sync/call_sync_fakes.dart';
import '../sim/sim_fakes.dart';
import '../workspace/fake_workspace_repository.dart';

class FakeAppSettingsStorage implements AppSettingsStorage {
  FakeAppSettingsStorage({this.saved, this.failRead = false, this.failWrite = false});

  String? saved;
  final bool failRead;
  final bool failWrite;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (failRead) throw Exception('read failed');
    return saved;
  }

  @override
  Future<void> write(String json) async {
    if (failWrite) throw Exception('write failed');
    writes++;
    saved = json;
  }
}

class FakeDeviceAuthenticator implements DeviceAuthenticator {
  FakeDeviceAuthenticator({this.supported = true, this.succeeds = true});

  bool supported;
  bool succeeds;
  final List<String> reasons = [];

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    return succeeds;
  }
}

class FakeServerPing implements ServerPing {
  FakeServerPing(this.milliseconds);

  final int? milliseconds;

  @override
  Future<int?> pingMilliseconds() async => milliseconds;
}

class FakeLocationService implements LocationService {
  FakeLocationService({this.granted = false});

  final bool granted;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<LocationResult?> requestAndGetLocation() async => null;
}

/// A container wired with in-memory fakes for everything the settings screens touch.
ProviderContainer settingsContainer({
  FakeAppSettingsStorage? storage,
  FakeDeviceAuthenticator? authenticator,
  FakeServerPing? ping,
  FakeAuthRepository? authRepo,
  bool locationGranted = false,
  FakeSimSelectionStorage? simStorage,
  FakeSimPlatformSource? simSource,
  FakeCallLogSource? callSyncSource,
  List<Override> extraOverrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      appSettingsStorageProvider.overrideWithValue(storage ?? FakeAppSettingsStorage()),
      deviceAuthenticatorProvider.overrideWithValue(authenticator ?? FakeDeviceAuthenticator()),
      serverPingProvider.overrideWithValue(ping ?? FakeServerPing(42)),
      authRepositoryProvider.overrideWithValue(authRepo ?? FakeAuthRepository()),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(FakeWorkspaceRepository()),
      leadLocationServiceProvider.overrideWithValue(FakeLocationService(granted: locationGranted)),
      // Settings shows the chosen business SIM; keep it off the real platform channels.
      simPlatformSourceProvider.overrideWithValue(simSource ?? FakeSimPlatformSource()),
      simSelectionStorageProvider.overrideWithValue(simStorage ?? FakeSimSelectionStorage()),
      // Settings shows call-sync rows; keep them off the platform/network too.
      ...callSyncOverrides(source: callSyncSource),
      ...extraOverrides,
    ],
  );
  return container;
}
