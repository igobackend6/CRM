import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/followups/domain/entities/follow_up_list_state.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_follow_up_repository.dart';
import 'followup_test_container.dart';

void main() {
  group('FollowUpListController', () {
    test('loads follow-ups on workspace selection', () async {
      final repo = FakeFollowUpRepository()
        ..itemsToReturn = [testFollowUp(id: 'fu-1')]
        ..totalToReturn = 1;
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpListControllerProvider).close);

      await waitUntil(() => container.read(followUpListControllerProvider).status == FollowUpListStatus.success);

      expect(container.read(followUpListControllerProvider).items.map((f) => f.id), ['fu-1']);
    });

    test('an empty result lands in the empty state', () async {
      final repo = FakeFollowUpRepository();
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpListControllerProvider).close);

      await waitUntil(() => container.read(followUpListControllerProvider).status == FollowUpListStatus.empty);
    });

    test('a failure lands in the error state with its message', () async {
      final repo = FakeFollowUpRepository()..listError = const NetworkException('Could not reach the server.');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpListControllerProvider).close);

      await waitUntil(() => container.read(followUpListControllerProvider).status == FollowUpListStatus.error);
      expect(container.read(followUpListControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('loadMore appends the next page', () async {
      final repo = FakeFollowUpRepository()
        ..itemsToReturn = [testFollowUp(id: 'fu-1')]
        ..totalToReturn = 2;
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpListControllerProvider).close);
      await waitUntil(() => container.read(followUpListControllerProvider).status == FollowUpListStatus.success);

      repo.itemsToReturn = [testFollowUp(id: 'fu-2')];
      await container.read(followUpListControllerProvider.notifier).loadMore();

      expect(repo.lastOffset, 1);
      expect(container.read(followUpListControllerProvider).items.map((f) => f.id), ['fu-1', 'fu-2']);
    });
  });
}
