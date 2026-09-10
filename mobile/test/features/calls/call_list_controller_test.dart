import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/calls/domain/entities/call_list_state.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';

import '../../helpers/wait_until.dart';
import 'call_test_container.dart';
import 'fake_call_repository.dart';

void main() {
  group('CallListController', () {
    test('loads calls on workspace selection', () async {
      final repo = FakeCallRepository()
        ..itemsToReturn = [testCall(id: 'call-1')]
        ..totalToReturn = 1;
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callListControllerProvider).close);

      await waitUntil(() => container.read(callListControllerProvider).status == CallListStatus.success);

      expect(container.read(callListControllerProvider).items.map((c) => c.id), ['call-1']);
    });

    test('an empty result lands in the empty state', () async {
      final repo = FakeCallRepository();
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callListControllerProvider).close);

      await waitUntil(() => container.read(callListControllerProvider).status == CallListStatus.empty);
    });

    test('a failure lands in the error state with its message', () async {
      final repo = FakeCallRepository()..listError = const NetworkException('Could not reach the server.');
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callListControllerProvider).close);

      await waitUntil(() => container.read(callListControllerProvider).status == CallListStatus.error);
      expect(container.read(callListControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('loadMore appends the next page', () async {
      final repo = FakeCallRepository()
        ..itemsToReturn = [testCall(id: 'call-1')]
        ..totalToReturn = 2;
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callListControllerProvider).close);
      await waitUntil(() => container.read(callListControllerProvider).status == CallListStatus.success);

      repo.itemsToReturn = [testCall(id: 'call-2')];
      await container.read(callListControllerProvider.notifier).loadMore();

      expect(repo.lastOffset, 1);
      expect(container.read(callListControllerProvider).items.map((c) => c.id), ['call-1', 'call-2']);
    });

    test('a lead-scoped controller filters by leadId server-side', () async {
      final repo = FakeCallRepository()
        ..itemsToReturn = [testCall(id: 'call-1', leadId: 'l1')]
        ..totalToReturn = 1;
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadCallListControllerProvider('l1')).close);

      await waitUntil(() => container.read(leadCallListControllerProvider('l1')).status == CallListStatus.success);

      expect(repo.lastListLeadId, 'l1');
    });
  });
}
