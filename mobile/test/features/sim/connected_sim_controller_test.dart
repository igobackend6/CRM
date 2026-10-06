import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';
import 'package:mobile/features/sim/presentation/controllers/connected_sim_controller.dart';

import 'sim_fakes.dart';

void main() {
  late FakeSimPlatformSource source;
  late FakeSimSelectionStorage storage;

  ConnectedSimController build({String? profileId = 'user-1'}) =>
      ConnectedSimController(SimRepository(source, storage), profileId);

  setUp(() {
    source = FakeSimPlatformSource(sims: [
      simMap(1, slot: 0, carrier: 'Jio', number: '+919800000001'),
      simMap(2, slot: 1, carrier: 'Airtel', number: '+919800000002'),
    ]);
    storage = FakeSimSelectionStorage();
  });

  test('a failed refresh keeps the SIMs already shown and reports it', () async {
    final controller = build();
    await controller.load();
    expect(controller.state.sims, hasLength(2));

    source.detectError = PlatformException(code: 'read_failed');
    await controller.refresh();

    expect(controller.state.status, ConnectedSimStatus.ready);
    expect(controller.state.sims, hasLength(2));
    expect(controller.state.notice, ConnectedSimController.readFailedMessage);
    expect(controller.state.refreshing, isFalse);
  });

  test('permission taken away in Android Settings: refresh falls back to the permission state', () async {
    final controller = build();
    await controller.load();

    source
      ..detectError = PlatformException(code: 'permission_denied')
      ..permission = 'permanentlyDenied';
    await controller.refresh();

    expect(controller.state.status, ConnectedSimStatus.permissionPermanentlyDenied);
    expect(controller.state.sims, isEmpty);
  });

  test('the selection survives a refresh where its SIM disappears, and comes back with it', () async {
    final controller = build();
    await controller.load();
    await controller.select(controller.state.sims.first);

    source.sims = [simMap(2, slot: 1, carrier: 'Airtel')];
    await controller.refresh();
    expect(controller.state.selectionUnavailable, isTrue);
    expect(controller.state.selection!.subscriptionId, 1);

    source.sims = [simMap(1, slot: 0, carrier: 'Jio', number: '+919800000001'), simMap(2, slot: 1, carrier: 'Airtel')];
    await controller.refresh();
    expect(controller.state.selectionUnavailable, isFalse);
    expect(controller.state.selectedSim!.subscriptionId, 1);
  });

  test('without a signed-in employee nothing is saved', () async {
    final controller = build(profileId: null);
    await controller.load();

    await controller.select(controller.state.sims.first);

    expect(storage.writes, 0);
    expect(controller.state.selection, isNull);
    expect(controller.state.notice, ConnectedSimController.saveFailedMessage);
  });

  test('an unreadable saved selection still lets detection run', () async {
    storage.failRead = true;
    final controller = build();
    await controller.load();

    expect(controller.state.status, ConnectedSimStatus.ready);
    expect(controller.state.selection, isNull);
  });

  test('a submitted number replaces only that SIM\'s number, and is kept per employee', () async {
    final controller = build();
    await controller.load();

    expect(await controller.submitNumber(controller.state.sims[1], '0 98765 43210'), isNull);
    expect(controller.state.numbers, {2: '+919876543210'});
    expect(controller.state.numberFor(controller.state.sims[0]), '+919800000001');

    final other = build(profileId: 'user-2');
    await other.load();
    expect(other.state.numbers, isEmpty);
  });

  test('a number cannot be saved while signed out, or when storage fails', () async {
    final signedOut = build(profileId: null);
    await signedOut.load();
    expect(await signedOut.submitNumber(signedOut.state.sims.first, '9876543210'), ConnectedSimController.numberSaveFailedMessage);

    storage.failWrite = true;
    final controller = build();
    await controller.load();
    expect(await controller.submitNumber(controller.state.sims.first, '9876543210'), ConnectedSimController.numberSaveFailedMessage);
    expect(controller.state.numbers, isEmpty);
  });

  test('re-selecting the current SIM does not write again', () async {
    final controller = build();
    await controller.load();
    await controller.select(controller.state.sims.first);
    await controller.select(controller.state.sims.first);

    expect(storage.writes, 1);
  });
}
