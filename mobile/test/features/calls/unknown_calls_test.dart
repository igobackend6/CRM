import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/router/route_paths.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/calls/domain/entities/call.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/calls/presentation/screens/call_list_screen.dart';
import 'package:mobile/features/calls/presentation/screens/call_number_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../call_sync/call_sync_fakes.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_call_repository.dart';

Map<String, dynamic> _json({Object? lead, String? contactName, String? phone}) => {
      'id': 'c1',
      'workspace_id': 'w1',
      'lead': lead,
      'contact_name': contactName,
      'phone_number': phone,
      'source': 'device_sync',
      'direction': 'inbound',
      'state': 'MISSED',
      'started_at': '2026-10-12T12:28:00Z',
      'created_at': '2026-10-12T12:30:00Z',
    };

/// A list with more pages to load shows a spinner that never stops, so pumpAndSettle would time out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, FakeCallRepository repo, Directory dir, {String start = '/'}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final authRepo = FakeAuthRepository()..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const CallListScreen()),
      GoRoute(path: '/app/call-number/:phone', builder: (_, s) => CallNumberScreen(phone: s.pathParameters['phone']!)),
      GoRoute(path: '/app/calls', builder: (_, s) => CallListScreen(phone: s.uri.queryParameters['phone'])),
      GoRoute(path: '/app/calls/:id', builder: (_, s) => Scaffold(body: Text('CALL DETAIL ${s.pathParameters['id']}'))),
      GoRoute(path: '/app/leads/:id', builder: (_, s) => Scaffold(body: Text('LEAD ${s.pathParameters['id']}'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        callRepositoryProvider.overrideWithValue(repo),
        ...callSyncOverrides(source: FakeCallLogSource(localDir: dir.path)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('unknown_calls_test'));
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows can still be finishing a write; a leftover temp folder is harmless.
    }
  });

  group('Call', () {
    test('a call with no lead reads fine: the contact name, else Unknown, and the number', () {
      final named = Call.fromJson(_json(contactName: 'Thara', phone: '+918072295987'));
      expect(named.hasLead, isFalse);
      expect(named.displayName, 'Thara');
      expect(named.formattedNumber, '+91 80722 95987');
      expect(named.phoneKey, '8072295987');
      expect(Call.fromJson(_json(contactName: '  ', phone: '+918072295987')).displayName, 'Unknown');
      expect(Call.fromJson(_json()).phoneKey, isNull);
    });

    test("a lead's call shows the lead's name", () {
      final call = Call.fromJson(_json(lead: {'id': 'l1', 'name': 'Suguna'}, contactName: null, phone: '+918925958929'));
      expect(call.hasLead, isTrue);
      expect(call.displayName, 'Suguna');
    });

    test("numbers are formatted like the phone's own log", () {
      expect(formatPhoneNumber('+918925878325'), '+91 89258 78325');
      expect(formatPhoneNumber('9876543210'), '98765 43210');
      expect(formatPhoneNumber('+14155550100'), '+14155550100');
      expect(formatPhoneNumber(null), isNull);
    });

    test('only an incoming call nobody picked up counts as missed', () {
      expect(testCall(direction: 'inbound', state: 'MISSED').isMissedIncoming, isTrue);
      expect(testCall(direction: 'inbound', state: 'CANCELLED').isMissedIncoming, isTrue);
      expect(testCall(direction: 'outbound', state: 'CANCELLED').isMissedIncoming, isFalse);
      expect(testCall(direction: 'inbound', state: 'ENDED').isMissedIncoming, isFalse);
    });
  });

  testWidgets("every call is listed: a lead's, an unknown number's, and a saved contact's", (tester) async {
    final repo = FakeCallRepository()
      ..itemsToReturn = [
        testCall(id: 'a', leadName: 'Suguna', phoneNumber: '+918925958929'),
        testCall(id: 'b', noLead: true, contactName: 'Unknown', phoneNumber: '+919818484388', direction: 'inbound'),
        testCall(id: 'c', noLead: true, contactName: 'Thara', phoneNumber: '+918072295987', direction: 'inbound', state: 'MISSED'),
      ]
      ..totalToReturn = 3;
    await _pump(tester, repo, dir);

    expect(find.byKey(const Key('call-name-a')), findsOneWidget);
    expect(find.text('Suguna'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Thara'), findsOneWidget);
    expect(find.text('+91 98184 84388'), findsOneWidget);
  });

  testWidgets("a missed incoming call is red, like the phone's call log", (tester) async {
    final repo = FakeCallRepository()
      ..itemsToReturn = [
        testCall(id: 'm', noLead: true, contactName: 'Unknown', phoneNumber: '+919074497360', direction: 'inbound', state: 'MISSED'),
        testCall(id: 'k', noLead: true, contactName: 'Unknown', phoneNumber: '+919818484388', direction: 'inbound', state: 'ENDED'),
      ]
      ..totalToReturn = 2;
    await _pump(tester, repo, dir);

    final missed = tester.widget<Text>(find.byKey(const Key('call-name-m')));
    final answered = tester.widget<Text>(find.byKey(const Key('call-name-k')));
    final error = Theme.of(tester.element(find.byKey(const Key('call-name-m')))).colorScheme.error;
    expect(missed.style?.color, error);
    expect(answered.style?.color, isNot(error));
  });

  testWidgets("the (i) icon opens that number's page, and View all lists every call to that number", (tester) async {
    final repo = FakeCallRepository()
      ..itemsToReturn = [testCall(id: 'b', noLead: true, contactName: 'Unknown', phoneNumber: '+919818484388', direction: 'inbound', durationSeconds: 67)]
      ..totalToReturn = 3;
    await _pump(tester, repo, dir);

    await tester.tap(find.byKey(const Key('call-info-b')));
    await _settle(tester);

    expect(find.byKey(const Key('call-number-name')), findsOneWidget);
    expect(find.text('+91 98184 84388'), findsWidgets);
    expect(repo.lastListPhone, '9818484388', reason: "the page asks only for this number's calls");
    expect(find.text('View all (3)'), findsOneWidget);
    expect(find.byKey(const Key('call-number-view-lead')), findsNothing, reason: 'an unknown number has no lead');

    await tester.tap(find.byKey(const Key('call-number-view-all')));
    await _settle(tester);
    expect(find.text('Call logs'), findsOneWidget);
    expect(repo.lastListPhone, '9818484388');
    // Already on the number's own list: no second (i) icon.
    expect(find.byKey(const Key('call-info-b')), findsNothing);
  });

  testWidgets('a number that is a lead offers View lead on its page', (tester) async {
    final repo = FakeCallRepository()
      ..itemsToReturn = [testCall(id: 'a', leadId: 'lead-9', leadName: 'Suguna', phoneNumber: '+918925958929')]
      ..totalToReturn = 1;
    await _pump(tester, repo, dir, start: RoutePaths.callNumber('8925958929'));

    expect(find.text('Suguna'), findsWidgets);
    await tester.tap(find.byKey(const Key('call-number-view-lead')));
    await _settle(tester);
    expect(find.text('LEAD lead-9'), findsOneWidget);
  });
}
