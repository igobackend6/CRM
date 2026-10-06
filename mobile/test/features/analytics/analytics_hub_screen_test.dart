import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/presentation/screens/analytics_hub_screen.dart';

import 'analytics_test_helpers.dart';

Future<void> _pump(WidgetTester tester, {String role = 'team_mate'}) =>
    pumpAnalytics(tester, screen: const AnalyticsHubScreen(), role: role);

void main() {
  testWidgets('lists the three analytics areas with their descriptions', (tester) async {
    await _pump(tester);

    expect(find.text('Analytics'), findsOneWidget); // app bar
    expect(find.text('Call Analytics'), findsOneWidget);
    expect(find.text('Measure call volume, connection rates, and talk time over selected time periods.'), findsOneWidget);
    expect(find.text('Customer Analytics'), findsOneWidget);
    expect(find.text('Track customer distribution by stage and status with clear funnel management.'), findsOneWidget);
    expect(find.text('User Performances'), findsOneWidget);
    expect(find.text('Identify top-performing agents by their call activity and customer engagement.'), findsOneWidget);
  });

  testWidgets('Call Analytics opens the call analytics screen', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('analytics-calls')));
    await tester.pumpAndSettle();

    expect(find.text(analyticsStubCalls), findsOneWidget);
  });

  testWidgets('Customer Analytics opens the customer analytics screen', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('analytics-customers')));
    await tester.pumpAndSettle();

    expect(find.text(analyticsStubCustomers), findsOneWidget);
  });

  group('User Performances', () {
    testWidgets('is open to a manager', (tester) async {
      await _pump(tester, role: 'manager');

      expect(find.byIcon(Icons.lock_outline), findsNothing);
      await tester.tap(find.byKey(const Key('analytics-users')));
      await tester.pumpAndSettle();

      expect(find.text(analyticsStubUsers), findsOneWidget);
    });

    for (final role in ['admin', 'ceo']) {
      testWidgets('is open to a $role', (tester) async {
        await _pump(tester, role: role);

        await tester.tap(find.byKey(const Key('analytics-users')));
        await tester.pumpAndSettle();

        expect(find.text(analyticsStubUsers), findsOneWidget);
      });
    }

    testWidgets('is locked for a team_mate: shows a lock, explains why, and does not navigate', (tester) async {
      await _pump(tester, role: 'team_mate');

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await tester.tap(find.byKey(const Key('analytics-users')));
      await tester.pumpAndSettle();

      expect(find.text('Manager access is required to view User Performances.'), findsOneWidget);
      expect(find.text(analyticsStubUsers), findsNothing);
    });

    testWidgets('is locked for a bd_data_team member too', (tester) async {
      await _pump(tester, role: 'bd_data_team');

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('the other two areas stay open for a team_mate', (tester) async {
      await _pump(tester, role: 'team_mate');

      await tester.tap(find.byKey(const Key('analytics-calls')));
      await tester.pumpAndSettle();

      expect(find.text(analyticsStubCalls), findsOneWidget);
    });
  });
}
