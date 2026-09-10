import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:mobile/main.dart';

import 'core/realtime/fake_realtime_service.dart';
import 'features/auth/fake_auth_repository.dart';
import 'features/workspace/fake_workspace_repository.dart';
import 'services/api/fake_me_api_data_source.dart';

void main() {
  testWidgets('Unauthenticated app boot lands on the Login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
          workspaceRepositoryProvider.overrideWithValue(FakeWorkspaceRepository()),
          realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
