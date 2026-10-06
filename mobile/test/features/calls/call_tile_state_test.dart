import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/calls/domain/entities/call.dart';
import 'package:mobile/features/calls/presentation/screens/call_list_screen.dart';
import 'package:mobile/features/followups/domain/entities/lead_summary.dart';

Call _call(String direction, String state) => Call(
      id: 'c1',
      workspaceId: 'ws',
      lead: const LeadSummary(id: 'l1', name: 'Ravi'),
      direction: direction,
      state: state,
      startedAt: DateTime(2026, 10, 1, 10),
      createdAt: DateTime(2026, 10, 1, 10),
    );

Future<void> _pump(WidgetTester tester, Call call) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: CallTile(call: call, showLeadName: false))));

void main() {
  testWidgets('calls synced from the phone say when they were missed, declined or not answered', (tester) async {
    for (final (direction, state, label) in [
      ('inbound', 'MISSED', 'Missed'),
      ('inbound', 'CANCELLED', 'Declined'),
      ('outbound', 'CANCELLED', 'Not answered'),
    ]) {
      await _pump(tester, _call(direction, state));
      expect(find.text(label), findsOneWidget, reason: '$direction $state');
    }
  });

  testWidgets('a normal finished call has no such label', (tester) async {
    await _pump(tester, _call('outbound', 'ENDED'));
    for (final label in ['Missed', 'Declined', 'Not answered']) {
      expect(find.text(label), findsNothing);
    }
  });
}
