import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/calls/domain/entities/call_detail_state.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';

import '../../helpers/wait_until.dart';
import 'call_test_container.dart';
import 'fake_call_repository.dart';

void main() {
  group('CallDetailController', () {
    test('loads the call', () async {
      final repo = FakeCallRepository()..callToReturn = testCall(id: 'call-1', leadName: 'Acme Corp');
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callDetailControllerProvider('call-1')).close);

      await waitUntil(() => container.read(callDetailControllerProvider('call-1')).status == CallDetailStatus.success);

      expect(container.read(callDetailControllerProvider('call-1')).call?.lead.name, 'Acme Corp');
    });

    test('a NotFoundException lands in notFound, not error', () async {
      final repo = FakeCallRepository()..getError = const NotFoundException('Call not found.');
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callDetailControllerProvider('missing')).close);

      await waitUntil(() => container.read(callDetailControllerProvider('missing')).status == CallDetailStatus.notFound);
    });

    test('a permission error lands in error with its message', () async {
      final repo = FakeCallRepository()..getError = const PermissionDeniedException('You do not have permission to do that.');
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callDetailControllerProvider('call-1')).close);

      await waitUntil(() => container.read(callDetailControllerProvider('call-1')).status == CallDetailStatus.error);
      expect(container.read(callDetailControllerProvider('call-1')).errorMessage, 'You do not have permission to do that.');
    });
  });
}
