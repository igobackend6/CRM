import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_csv_file_picker.dart';
import 'fake_lead_filter_storage.dart';
import 'fake_lead_repository.dart';

/// A ProviderContainer with a real, authenticated session and a single
/// selected workspace already established — everything Phase 5's
/// controllers need from resolveLeadContext(). Uses the real
/// AuthController/WorkspaceController wiring (not hand-rolled fakes of
/// their state), same principle as workspace_controller_test.dart.
Future<ProviderContainer> buildLeadTestContainer({
  FakeLeadRepository? leadRepository,
  FakeCsvFilePicker? csvFilePicker,
  FakeLeadFilterStorage? leadFilterStorage,
  FakeRealtimeService? realtimeService,
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      leadRepositoryProvider.overrideWithValue(leadRepository ?? FakeLeadRepository()),
      csvFilePickerProvider.overrideWithValue(csvFilePicker ?? FakeCsvFilePicker()),
      leadFilterStorageProvider.overrideWithValue(leadFilterStorage ?? FakeLeadFilterStorage()),
      // Phase 21B: a plain fake event bus, not the real RealtimeService
      // (which needs an initialized supabase_flutter client) — read it
      // back via `container.read(realtimeServiceProvider)` and cast to
      // FakeRealtimeService to emit a simulated event in a test.
      realtimeServiceProvider.overrideWithValue(realtimeService ?? FakeRealtimeService()),
    ],
  );

  // Let auth establish + workspace auto-select settle before the test
  // drives a leads controller that depends on both.
  await waitUntil(() => container.read(workspaceControllerProvider).selected != null);
  return container;
}

/// Every leads controller provider is `.autoDispose` (screen-scoped in
/// production). A bare `container.read(...)` in a test doesn't hold a
/// subscription, so Riverpod disposes it again almost immediately —
/// then a pending async callback inside the controller crashes with
/// "used after dispose". `container.listen(...)` keeps it alive for the
/// life of the returned subscription; close it in `addTearDown`.
ProviderSubscription<T> keepAlive<T>(ProviderContainer container, ProviderListenable<T> provider) {
  return container.listen(provider, (_, _) {});
}
