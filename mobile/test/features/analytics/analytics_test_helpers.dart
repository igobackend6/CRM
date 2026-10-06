import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/core/router/route_paths.dart';
import 'package:mobile/features/activity/presentation/controllers/activity_controller.dart';
import 'package:mobile/features/activity/presentation/providers/activity_providers.dart';
import 'package:mobile/features/analytics/data/file_saver.dart';
import 'package:mobile/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/reports/presentation/providers/reports_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../activity/fake_activity_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../reports/fake_reports_repository.dart';
import '../workspace/fake_workspace_repository.dart';

/// Records what would have been written to disk and lets a test choose
/// whether the user "saved", cancelled, or the platform call failed.
class FakeFileSaver implements FileSaver {
  bool saved = true;
  Object? error;

  /// When set, saveBytes waits on it (after recording the call), so a test
  /// can observe the in-flight state before completing the dialog.
  Completer<bool>? hold;
  String? lastFileName;
  Uint8List? lastBytes;
  String? lastMimeType;
  int callCount = 0;

  /// The saved bytes read back as UTF-8 text (for the CSV export).
  String? get lastText => lastBytes == null ? null : utf8.decode(lastBytes!);

  @override
  Future<bool> saveBytes({required String fileName, required Uint8List bytes, required String mimeType}) async {
    callCount++;
    lastFileName = fileName;
    lastBytes = bytes;
    lastMimeType = mimeType;
    if (error != null) throw error!;
    if (hold != null) return hold!.future;
    return saved;
  }
}

/// Text shown by the stub destinations so navigation can be asserted
/// without building the real screens.
const analyticsStubCalls = 'STUB: call analytics';
const analyticsStubCustomers = 'STUB: customer analytics';
const analyticsStubUsers = 'STUB: user performances';

/// Pumps [screen] at `/` inside a real authenticated session (one selected
/// workspace, membership role [role]) with the reports repository and the
/// file saver faked. The three analytics destinations are stubbed so a
/// hub test can tap through.
///
/// The workspace is established *before* the screen is built, matching the
/// app: the route guard never lets a user reach an analytics screen until a
/// workspace is selected, so `roleName` is never null at first build.
Future<void> pumpAnalytics(
  WidgetTester tester, {
  required Widget screen,
  FakeReportsRepository? repository,
  String role = 'team_mate',
  FakeFileSaver? saver,
  FakeActivityRepository? activity,
}) async {
  final activityRepo = activity ?? FakeActivityRepository();
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'), role: role)];

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      reportsRepositoryProvider.overrideWithValue(repository ?? FakeReportsRepository()),
      fileSaverProvider.overrideWithValue(saver ?? FakeFileSaver()),
      activityRepositoryProvider.overrideWithValue(activityRepo),
      // The real controller's once-a-minute timer would still be pending
      // when the test ends (the container is only disposed afterwards), so
      // widget tests get one that never ticks. The controller's own timing
      // is covered in activity_controller_test.dart.
      activityControllerProvider.overrideWith(
        (ref) => ActivityController(activityRepo, ref, startTimer: (interval, onTick) => Timer(Duration.zero, () {})..cancel()),
      ),
      realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
    ],
  );
  addTearDown(container.dispose);

  // Instantiate the controllers and let the (synchronous-future) fakes
  // finish signing in and selecting the workspace.
  container.read(workspaceControllerProvider);
  for (var i = 0; i < 20 && container.read(workspaceControllerProvider).selected == null; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(container.read(workspaceControllerProvider).selected, isNotNull, reason: 'test harness: workspace never selected');

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => screen),
      GoRoute(path: RoutePaths.analyticsCalls, builder: (context, state) => const Scaffold(body: Text(analyticsStubCalls))),
      GoRoute(path: RoutePaths.analyticsCustomers, builder: (context, state) => const Scaffold(body: Text(analyticsStubCustomers))),
      GoRoute(path: RoutePaths.analyticsUsers, builder: (context, state) => const Scaffold(body: Text(analyticsStubUsers))),
      GoRoute(path: RoutePaths.analytics, builder: (context, state) => const Scaffold(body: Text('STUB: analytics hub'))),
    ],
  );

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}
