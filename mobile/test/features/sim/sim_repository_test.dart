import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';
import 'package:mobile/features/sim/domain/business_sim_selection.dart';
import 'package:mobile/features/sim/domain/sim_card.dart';
import 'package:mobile/features/sim/domain/sim_number.dart';
import 'package:mobile/features/sim/domain/sim_permission_status.dart';

import 'sim_fakes.dart';

void main() {
  late FakeSimPlatformSource source;
  late FakeSimSelectionStorage storage;
  late SimRepository repo;
  final now = DateTime(2026, 10, 1, 10, 30);

  setUp(() {
    source = FakeSimPlatformSource();
    storage = FakeSimSelectionStorage();
    repo = SimRepository(source, storage, random: Random(1), clock: () => now);
  });

  tearDown(() {
    AppLogger.capture = false;
    AppLogger.clearBuffer();
  });

  group('mapping', () {
    test('maps every field the bridge sends', () {
      final sim = SimRepository.simFromPlatform(simMap(3, slot: 1, carrier: 'Airtel', display: 'Work', number: '+919800000002'))!;

      expect(sim.subscriptionId, 3);
      expect(sim.slotIndex, 1);
      expect(sim.simLabel, 'SIM 2');
      expect(sim.slotLabel, 'Slot 2');
      expect(sim.carrierName, 'Airtel');
      expect(sim.displayName, 'Work');
      expect(sim.phoneNumber, '+919800000002');
      expect(sim.simState, 'ready');
      expect(sim.isActive, isTrue);
    });

    test('partial info stays null instead of being made up', () {
      final sim = SimRepository.simFromPlatform({'subscriptionId': 5, 'carrierName': '  ', 'phoneNumber': ''})!;

      expect(sim.slotIndex, isNull);
      expect(sim.simLabel, 'SIM');
      expect(sim.slotLabel, isNull);
      expect(sim.carrierName, isNull);
      expect(sim.operatorName, isNull);
      expect(sim.phoneNumber, isNull);
      expect(sim.simState, isNull);
    });

    test('falls back to the display name when no carrier is reported', () {
      final sim = SimRepository.simFromPlatform(simMap(1, slot: 0, display: 'Jio 4G'))!;
      expect(sim.operatorName, 'Jio 4G');
    });

    test('drops entries without a usable subscription id, wrong types and duplicates; orders by slot', () {
      final sims = SimRepository.simsFromPlatform([
        simMap(9, carrier: 'eSIM'),
        'garbage',
        {'subscriptionId': 'x'},
        {'subscriptionId': -1},
        {'subscriptionId': 4, 'slotIndex': 'one', 'carrierName': 7},
        simMap(2, slot: 1, carrier: 'Airtel'),
        simMap(1, slot: 0, carrier: 'Jio'),
        simMap(1, slot: 0, carrier: 'Duplicate'),
      ]);

      expect(sims.map((s) => s.subscriptionId), [1, 2, 4, 9]);
      expect(sims.first.carrierName, 'Jio');
      expect(sims[2].slotIndex, isNull);
      expect(sims[2].carrierName, isNull);
    });

    test('a non-list answer means no SIMs', () {
      expect(SimRepository.simsFromPlatform(null), isEmpty);
      expect(SimRepository.simsFromPlatform({'a': 1}), isEmpty);
    });

    test('a non-ready SIM state is described', () {
      expect(const SimCard(subscriptionId: 1, simState: 'pinRequired').stateProblem, 'SIM PIN required');
      expect(const SimCard(subscriptionId: 1, simState: 'ready').stateProblem, isNull);
    });
  });

  group('typed numbers', () {
    test('a 10-digit number gets +91; spaces, dashes and a leading 0 are fine', () {
      expect(normalizeSimNumber('9876543210'), '+919876543210');
      expect(normalizeSimNumber(' 98765-43210 '), '+919876543210');
      expect(normalizeSimNumber('09876543210'), '+919876543210');
      expect(normalizeSimNumber('+91 98765 43210'), '+919876543210');
    });

    test('too short, empty or junk is refused', () {
      expect(normalizeSimNumber(''), isNull);
      expect(normalizeSimNumber('12345'), isNull);
      expect(normalizeSimNumber('abc'), isNull);
    });
  });

  group('permission', () {
    test('parses each status, and an unknown answer counts as denied', () async {
      for (final (raw, expected) in [
        ('granted', SimPermissionStatus.granted),
        ('notRequested', SimPermissionStatus.notRequested),
        ('denied', SimPermissionStatus.denied),
        ('permanentlyDenied', SimPermissionStatus.permanentlyDenied),
        ('unavailable', SimPermissionStatus.unavailable),
        ('weird', SimPermissionStatus.denied),
        (null, SimPermissionStatus.denied),
      ]) {
        source.permission = raw;
        expect(await repo.permissionStatus(), expected, reason: '$raw');
      }
    });

    test('request returns the status after the dialog', () async {
      source
        ..permission = 'notRequested'
        ..afterRequest = 'denied';
      expect(await repo.requestPermission(), SimPermissionStatus.denied);
      expect(source.requestCalls, 1);
    });
  });

  group('detection errors', () {
    Future<SimReadFailure> failureFor(Object error) async {
      source.detectError = error;
      try {
        await repo.detectActiveSims();
      } on SimReadException catch (e) {
        return e.failure;
      }
      fail('expected a SimReadException');
    }

    test('platform errors become friendly failures', () async {
      expect(await failureFor(PlatformException(code: 'permission_denied')), SimReadFailure.permissionDenied);
      expect(await failureFor(PlatformException(code: 'unavailable')), SimReadFailure.unavailable);
      expect(await failureFor(PlatformException(code: 'read_failed')), SimReadFailure.readFailed);
      expect(await failureFor(MissingPluginException()), SimReadFailure.unavailable);
      expect(await failureFor(StateError('boom')), SimReadFailure.readFailed);
    });

    test('logs counts only — never the number or carrier', () async {
      AppLogger.capture = true;
      source.sims = [simMap(1, slot: 0, carrier: 'Jio', number: '+919800000001')];

      await repo.detectActiveSims();

      final log = AppLogger.bufferedLines.join('\n');
      expect(log, contains('1 active subscription'));
      expect(log, isNot(contains('9800000001')));
      expect(log, isNot(contains('Jio')));
    });
  });

  group('selection persistence', () {
    const jio = SimCard(subscriptionId: 1, slotIndex: 0, carrierName: 'Jio', phoneNumber: '+919800000001');
    const airtel = SimCard(subscriptionId: 2, slotIndex: 1, carrierName: 'Airtel');

    test('nothing saved means nothing selected', () async {
      expect(await repo.loadSelection('user-1'), isNull);
    });

    test('saves the choice per employee, without the phone number', () async {
      final saved = await repo.select('user-1', jio);

      expect(saved.subscriptionId, 1);
      expect(saved.summary, 'Jio • SIM 1');
      expect(saved.selectedAt, now);
      expect(storage.saved, isNot(contains('9800000001')));

      final loaded = (await repo.loadSelection('user-1'))!;
      expect(loaded.subscriptionId, 1);
      expect(loaded.carrierName, 'Jio');
      expect(loaded.slotIndex, 0);
      expect(loaded.deviceInstallId, saved.deviceInstallId);
    });

    test('choosing another SIM replaces only that employee\'s choice', () async {
      await repo.select('user-1', jio);
      await repo.select('user-2', jio);
      await repo.select('user-1', airtel);

      expect((await repo.loadSelection('user-1'))!.subscriptionId, 2);
      expect((await repo.loadSelection('user-2'))!.subscriptionId, 1);
    });

    test('a random install id is created once and reused (no hardware identifier)', () async {
      final first = await repo.select('user-1', jio);
      final second = await repo.select('user-1', airtel);

      expect(first.deviceInstallId, hasLength(32));
      expect(first.deviceInstallId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second.deviceInstallId, first.deviceInstallId);
      expect((jsonDecode(storage.saved!) as Map)['installId'], first.deviceInstallId);
    });

    test('a corrupted save is treated as nothing selected, and can be overwritten', () async {
      storage.saved = '{not json';
      expect(await repo.loadSelection('user-1'), isNull);

      storage.saved = jsonEncode({
        'selections': {'user-1': {'subscriptionId': 'one'}},
      });
      expect(await repo.loadSelection('user-1'), isNull);

      await repo.select('user-1', jio);
      expect((await repo.loadSelection('user-1'))!.subscriptionId, 1);
    });

    test('a failed write surfaces as an error', () async {
      storage.failWrite = true;
      expect(() => repo.select('user-1', jio), throwsException);
    });

    test('numbers are saved per employee and per SIM, next to the selection', () async {
      await repo.select('user-1', jio);
      await repo.saveNumber('user-1', 1, '+919800000001');
      await repo.saveNumber('user-1', 2, '+919800000002');
      await repo.saveNumber('user-2', 1, '+919999999999');
      await repo.saveNumber('user-1', 2, '+919800000003');

      expect(await repo.loadNumbers('user-1'), {1: '+919800000001', 2: '+919800000003'});
      expect(await repo.loadNumbers('user-2'), {1: '+919999999999'});
      expect(await repo.loadNumbers('nobody'), isEmpty);
      expect((await repo.loadSelection('user-1'))!.subscriptionId, 1);
    });

    test('unreadable saved numbers are ignored', () async {
      storage.saved = jsonEncode({
        'numbers': {'user-1': {'x': '+91', '3': 7, '4': '+919800000004'}},
      });
      expect(await repo.loadNumbers('user-1'), {4: '+919800000004'});
    });

    test('selection round-trips through JSON', () {
      final selection = BusinessSimSelection(subscriptionId: 7, deviceInstallId: 'abc', selectedAt: now, carrierName: 'Vi');
      final back = BusinessSimSelection.fromJson(jsonDecode(jsonEncode(selection.toJson())))!;
      expect(back.subscriptionId, 7);
      expect(back.selectedAt, now);
      expect(back.summary, 'Vi • SIM');
    });
  });
}
