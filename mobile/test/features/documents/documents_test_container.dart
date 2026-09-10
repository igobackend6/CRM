import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/utils/external_url_launcher.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/documents/data/document_file_picker.dart';
import 'package:mobile/features/documents/domain/entities/picked_document_file.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_document_repository.dart';

class _NoOpDocumentFilePicker implements DocumentFilePicker {
  @override
  Future<PickedDocumentFile?> pickDocumentFile() async => null;
}

class _NoOpExternalUrlLauncher implements ExternalUrlLauncher {
  @override
  Future<bool> launch(Uri uri) async => true;
}

/// Mirrors customer360_test_container.dart's buildCustomerTestContainer
/// — a real, authenticated session with a single selected workspace
/// already established, so DocumentListController's resolveLeadContext()
/// resolves immediately. `filePicker`/`launcher` default to harmless
/// no-ops (never touching the real file_picker/url_launcher plugins,
/// which need platform channels `flutter test` doesn't provide) —
/// override them only in tests that specifically exercise upload/open.
Future<ProviderContainer> buildDocumentsTestContainer({
  FakeDocumentRepository? documentRepository,
  DocumentFilePicker? filePicker,
  ExternalUrlLauncher? launcher,
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      documentRepositoryProvider.overrideWithValue(documentRepository ?? FakeDocumentRepository()),
      documentFilePickerProvider.overrideWithValue(filePicker ?? _NoOpDocumentFilePicker()),
      documentExternalUrlLauncherProvider.overrideWithValue(launcher ?? _NoOpExternalUrlLauncher()),
    ],
  );

  await waitUntil(() => container.read(workspaceControllerProvider).selected != null);
  return container;
}

ProviderSubscription<T> keepAlive<T>(ProviderContainer container, ProviderListenable<T> provider) {
  return container.listen(provider, (_, _) {});
}
