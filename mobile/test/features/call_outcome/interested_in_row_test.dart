import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/call_outcome/presentation/widgets/interested_in_row.dart';
import 'package:mobile/features/custom_fields/domain/entities/custom_field.dart';
import 'package:mobile/features/custom_fields/presentation/providers/custom_field_providers.dart';

CustomField _field() => CustomField.fromJson({
      'id': 'f1',
      'name': 'Interested In',
      'code': 'interested_in',
      'field_type': 'options',
      'sort_order': 1,
      'options': [
        {'code': 'nursery', 'label': 'Nursery'},
        {'code': 'polyhouse', 'label': 'Polyhouse'},
      ],
    });

Future<void> _pump(WidgetTester tester, Map<String, dynamic> values, {List<CustomField>? fields}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [workspaceCustomFieldsProvider.overrideWith((ref) async => fields ?? [_field()])],
      child: MaterialApp(home: Scaffold(body: CustomFieldRows(customFields: values))),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpChip(WidgetTester tester, Map<String, dynamic> values) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [workspaceCustomFieldsProvider.overrideWith((ref) async => [_field()])],
      child: MaterialApp(home: Scaffold(body: InterestedInChip(customFields: values))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the header chip shows the project name', (tester) async {
    await _pumpChip(tester, {'interested_in': 'nursery'});
    expect(find.byKey(const Key('interested-in-chip')), findsOneWidget);
    expect(find.text('Nursery'), findsOneWidget);
  });

  testWidgets('the header chip is absent when no project is saved', (tester) async {
    await _pumpChip(tester, {});
    expect(find.byKey(const Key('interested-in-chip')), findsNothing);
  });

  testWidgets('shows the label of the saved option', (tester) async {
    await _pump(tester, {'interested_in': 'polyhouse'});
    expect(find.text('Interested In'), findsOneWidget);
    expect(find.text('Polyhouse'), findsOneWidget);
  });

  testWidgets('nothing saved shows a dash', (tester) async {
    await _pump(tester, {});
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('a value that matches no option is shown as stored', (tester) async {
    await _pump(tester, {'interested_in': 'Joint venture'});
    expect(find.text('Joint venture'), findsOneWidget);
  });

  testWidgets('every admin field gets a row, including ones added later, in the admin order', (tester) async {
    final extra = CustomField.fromJson({'id': 'f2', 'name': 'Budget', 'code': 'budget', 'field_type': 'number', 'sort_order': 2});
    final status = CustomField.fromJson({
      'id': 'f3',
      'name': 'Status',
      'code': 'status',
      'field_type': 'options',
      'sort_order': 3,
      'options': [
        {'code': 'interested', 'label': 'Interested'},
      ],
    });
    await _pump(tester, {'interested_in': 'nursery', 'budget': 250000, 'status': 'interested'}, fields: [status, extra, _field()]);
    expect(find.text('Nursery'), findsOneWidget);
    expect(find.text('250000'), findsOneWidget);
    expect(find.text('Interested'), findsOneWidget);
    final y = (String code) => tester.getTopLeft(find.byKey(Key('custom-field-row-$code'))).dy;
    expect(y('interested_in') < y('budget') && y('budget') < y('status'), isTrue);
  });

  testWidgets('a workspace with no admin fields shows no rows', (tester) async {
    await _pump(tester, {'interested_in': 'nursery'}, fields: const []);
    expect(find.text('Interested In'), findsNothing);
  });
}
