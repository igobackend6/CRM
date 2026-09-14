import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/whatsapp/presentation/providers/whatsapp_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_message_template_repository.dart';

Future<ProviderContainer> buildWhatsAppTestContainer({FakeMessageTemplateRepository? templateRepository}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      messageTemplateRepositoryProvider.overrideWithValue(templateRepository ?? FakeMessageTemplateRepository()),
    ],
  );

  await waitUntil(() => container.read(workspaceControllerProvider).selected != null);
  return container;
}

ProviderSubscription<T> keepAlive<T>(ProviderContainer container, ProviderListenable<T> provider) {
  return container.listen(provider, (_, _) {});
}
