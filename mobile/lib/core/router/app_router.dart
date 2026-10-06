import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Curves, CurvedAnimation, FadeTransition, Interval, Offset, SlideTransition, Tween;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/presentation/providers/activity_providers.dart';
import '../../features/analytics/presentation/screens/analytics_hub_screen.dart';
import '../../features/analytics/presentation/screens/call_analytics_screen.dart';
import '../../features/analytics/presentation/screens/customer_analytics_screen.dart';
import '../../features/analytics/presentation/screens/user_performances_screen.dart';
import '../../features/app_shell/presentation/screens/app_shell_scaffold.dart';
import '../../features/app_shell/presentation/screens/app_shell_screen.dart';
import '../../features/app_shell/presentation/screens/menu_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/call_outcome/presentation/providers/call_outcome_providers.dart';
import '../../features/auth/presentation/screens/change_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/calls/presentation/screens/call_detail_screen.dart';
import '../../features/calls/presentation/screens/call_form_screen.dart';
import '../../features/calls/presentation/screens/call_list_screen.dart';
import '../../features/customer360/presentation/screens/customer_detail_screen.dart';
import '../../features/customer360/presentation/screens/customers_overview_screen.dart';
import '../../features/dialer/presentation/screens/dialer_screen.dart';
import '../../features/followups/presentation/screens/follow_up_detail_screen.dart';
import '../../features/followups/presentation/screens/follow_up_form_screen.dart';
import '../../features/followups/presentation/screens/follow_up_list_screen.dart';
import '../../features/leads/presentation/screens/lead_detail_screen.dart';
import '../../features/leads/presentation/screens/lead_form_screen.dart';
import '../../features/leads/presentation/screens/lead_list_screen.dart';
import '../../features/messaging/presentation/screens/conversation_detail_screen.dart';
import '../../features/messaging/presentation/screens/conversation_list_screen.dart';
import '../../features/notifications/presentation/screens/notification_list_screen.dart';
import '../../features/onboarding/presentation/providers/onboarding_providers.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/pipeline/presentation/screens/pipeline_screen.dart';
import '../../features/push/presentation/providers/push_providers.dart';
import '../../features/rechurn/presentation/screens/rechurn_queue_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/settings/presentation/providers/settings_providers.dart';
import '../../features/settings/presentation/screens/app_security_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/troubleshooting_screen.dart';
import '../../features/call_sync/presentation/screens/call_sync_screen.dart';
import '../../features/call_sync/presentation/screens/import_recording_screen.dart';
import '../../features/dialer/presentation/screens/default_dialer_screen.dart';
import '../../features/call_sync/presentation/screens/never_attended_screen.dart';
import '../../features/call_sync/presentation/screens/not_sync_screen.dart';
import '../../features/sim/presentation/screens/connected_sim_screen.dart';
import '../../features/whatsapp/presentation/screens/message_templates_screen.dart';
import '../../features/workspace/presentation/providers/workspace_providers.dart';
import '../../features/workspace/presentation/screens/workspace_selection_screen.dart';
import '../realtime/realtime_providers.dart';
import 'placeholder_screens.dart';
import 'route_guard.dart';
import 'route_paths.dart';

/// Bridges Riverpod state changes into GoRouter's `refreshListenable`,
/// so a redirect is re-evaluated whenever auth or workspace state
/// changes — not just on explicit navigation.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(workspaceControllerProvider, (_, _) => notifyListeners());
    ref.listen(onboardingControllerProvider, (_, _) => notifyListeners());
    // Boots the app-lifetime Realtime service (Phase 21B) — this is the
    // one existing cross-cutting auth/workspace listener, so it's the
    // natural place to instantiate `realtimeServiceProvider` at app
    // start, mirroring `SupabaseService.initialize()`'s timing intent.
    ref.read(realtimeServiceProvider);
    // Same rationale — keeps the backend's device_tokens in sync with
    // this device's FCM token across login/logout (Phase 4). A quiet
    // no-op until a Firebase project is wired.
    ref.read(pushRegistrarProvider);
    // Login Analytics: checks in with the backend once a minute while
    // signed in (foreground or background) and reports sign-out.
    ref.read(activityControllerProvider);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RoutePaths.splash,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final workspace = ref.read(workspaceControllerProvider);
      final onboarding = ref.read(onboardingControllerProvider);
      final target = resolveRedirect(auth: auth, workspace: workspace, location: state.matchedLocation, onboarding: onboarding);
      return applyDefaultScreen(target, ref.read(appSettingsControllerProvider).defaultScreen);
    },
    routes: [
      GoRoute(path: RoutePaths.root, builder: (context, state) => const SplashScreen()),
      GoRoute(path: RoutePaths.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: RoutePaths.onboarding, builder: (context, state) => const OnboardingScreen()),
      // The login screen "falls" in from the top and bounces to rest — the
      // hand-off from the onboarding slides' "Get Started" button.
      GoRoute(
        path: RoutePaths.login,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const LoginScreen(),
          transitionDuration: const Duration(milliseconds: 900),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fall = CurvedAnimation(parent: animation, curve: Curves.bounceOut, reverseCurve: Curves.easeIn);
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.3)),
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(fall),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(path: RoutePaths.changePassword, builder: (context, state) => const ChangePasswordScreen()),
      GoRoute(path: RoutePaths.workspace, builder: (context, state) => const WorkspaceSelectionScreen()),
      // The bottom-nav shell (Runo-reference footer) — Home / Allocations
      // / Customers / Menu, in that order, matching `AppNavTab`'s
      // declaration order exactly (`AppShellScaffold` indexes into it by
      // `navigationShell.currentIndex`). `indexedStack` keeps all four
      // branches' Navigators alive at once (an `IndexedStack`, not a
      // rebuild-on-switch), so each tab keeps its own scroll position
      // and back stack across tab switches — including a branch's own
      // nested routes (Lead Detail/Edit, Customer Detail), which is why
      // those live inside their branch's `routes:` here rather than as
      // separate top-level routes. Every route declared OUTSIDE this
      // shell (Reports, Calls, ...) still pushes on the root navigator
      // as before, over the whole shell — the bar intentionally isn't
      // part of those.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShellScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: RoutePaths.app, builder: (context, state) => const AppShellScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.leads,
                builder: (context, state) => const LeadListScreen(),
                routes: [
                  // Declared before the `:id` child so a literal
                  // "create" segment matches this route, not the `:id`
                  // pattern below. `extra` carries a phone number typed
                  // into the dialer's "Create new customer" shortcut
                  // (RoutePaths.dialer) — null for every other caller.
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => LeadFormScreen(initialPhone: state.extra as String?),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => LeadDetailScreen(leadId: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => LeadFormScreen(leadId: state.pathParameters['id']),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.customers,
                builder: (context, state) => const CustomersOverviewScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => CustomerDetailScreen(customerId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: RoutePaths.menu, builder: (context, state) => const MenuScreen())],
          ),
        ],
      ),
      // `extra` is a number another app asked the dialer to show (a tel: link), or null.
      GoRoute(path: RoutePaths.dialer, builder: (context, state) => DialerScreen(initialNumber: state.extra as String?)),
      GoRoute(path: RoutePaths.defaultDialer, builder: (context, state) => const DefaultDialerScreen()),
      GoRoute(path: RoutePaths.pipeline, builder: (context, state) => const PipelineScreen()),
      GoRoute(path: RoutePaths.rechurn, builder: (context, state) => const RechurnQueueScreen()),
      GoRoute(path: RoutePaths.reports, builder: (context, state) => const ReportsScreen()),
      GoRoute(path: RoutePaths.settings, builder: (context, state) => const SettingsScreen()),
      GoRoute(path: RoutePaths.troubleshooting, builder: (context, state) => const TroubleshootingScreen()),
      GoRoute(path: RoutePaths.appSecurity, builder: (context, state) => const AppSecurityScreen()),
      GoRoute(path: RoutePaths.connectedSim, builder: (context, state) => const ConnectedSimScreen()),
      GoRoute(path: RoutePaths.callSync, builder: (context, state) => const CallSyncScreen()),
      GoRoute(path: RoutePaths.notSync, builder: (context, state) => const NotSyncScreen()),
      GoRoute(path: RoutePaths.neverAttended, builder: (context, state) => const NeverAttendedScreen()),
      GoRoute(path: RoutePaths.importRecording, builder: (context, state) => const ImportRecordingScreen()),
      GoRoute(
        path: RoutePaths.analytics,
        builder: (context, state) => const AnalyticsHubScreen(),
        routes: [
          GoRoute(path: 'calls', builder: (context, state) => const CallAnalyticsScreen()),
          GoRoute(path: 'customers', builder: (context, state) => const CustomerAnalyticsScreen()),
          GoRoute(path: 'users', builder: (context, state) => const UserPerformancesScreen()),
        ],
      ),
      GoRoute(
        path: RoutePaths.followUps,
        builder: (context, state) => const FollowUpListScreen(),
        routes: [
          // Declared before the `:id` child, same reasoning as leads'
          // "create" route above.
          GoRoute(
            path: 'create',
            builder: (context, state) => FollowUpFormScreen(leadId: state.uri.queryParameters['leadId']),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => FollowUpDetailScreen(followUpId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => FollowUpFormScreen(followUpId: state.pathParameters['id']),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: RoutePaths.notifications, builder: (context, state) => const NotificationListScreen()),
      GoRoute(
        path: RoutePaths.calls,
        builder: (context, state) => CallListScreen(leadId: state.uri.queryParameters['leadId']),
        routes: [
          // Declared before the `:id` child, same reasoning as leads'/
          // follow-ups' "create" routes above.
          GoRoute(
            path: 'create',
            builder: (context, state) => CallFormScreen(leadId: state.uri.queryParameters['leadId']),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => CallDetailScreen(callId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.messages,
        builder: (context, state) => const ConversationListScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => ConversationDetailScreen(conversationId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: RoutePaths.messageTemplates, builder: (context, state) => const MessageTemplatesScreen()),
    ],
  );
});
