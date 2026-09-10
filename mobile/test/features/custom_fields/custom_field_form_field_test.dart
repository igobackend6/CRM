import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/custom_fields/domain/entities/custom_field.dart';
import 'package:mobile/features/custom_fields/presentation/widgets/custom_field_form_field.dart';

CustomField _field(
  String code,
  String type, {
  List<CustomFieldOption> options = const [],
  bool mandatory = false,
  bool readonly = false,
}) =>
    CustomField(
      id: code,
      name: code.replaceAll('_', ' '),
      code: code,
      fieldType: type,
      options: options,
      autoFill: true,
      isFilterable: false,
      isReadonly: readonly,
      isMandatory: mandatory,
      sortOrder: 0,
    );

Future<void> _pump(WidgetTester tester, CustomField field, {Object? initial, required void Function(Object?) onChanged}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Form(
          child: CustomFieldFormField(field: field, initialValue: initial, onChanged: onChanged),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('text field reports the typed value', (tester) async {
    Object? captured;
    await _pump(tester, _field('nickname', 'text'), onChanged: (v) => captured = v);

    await tester.enterText(find.byType(TextFormField), 'Ace');
    expect(captured, 'Ace');
  });

  testWidgets('number field parses to a num and rejects non-numbers on validate', (tester) async {
    Object? captured;
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: key,
            child: CustomFieldFormField(field: _field('size', 'number'), initialValue: null, onChanged: (v) => captured = v),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '4200');
    expect(captured, 4200);

    await tester.enterText(find.byType(TextFormField), 'lots');
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter a number.'), findsOneWidget);
  });

  testWidgets('options field renders a dropdown of the labels', (tester) async {
    await _pump(
      tester,
      _field('segment', 'options', options: const [
        CustomFieldOption(code: 'smb', label: 'SMB'),
        CustomFieldOption(code: 'ent', label: 'Enterprise'),
      ]),
      onChanged: (_) {},
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Enterprise').hitTestable(), findsOneWidget);
  });

  testWidgets('multi_options renders a chip per option and toggling reports a list', (tester) async {
    Object? captured;
    await _pump(
      tester,
      _field('interests', 'multi_options', options: const [
        CustomFieldOption(code: 'a', label: 'Alpha'),
        CustomFieldOption(code: 'b', label: 'Beta'),
      ]),
      onChanged: (v) => captured = v,
    );

    expect(find.byType(FilterChip), findsNWidgets(2));
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(captured, ['b']);
  });

  testWidgets('a mandatory field fails validation when empty', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: key,
            child: CustomFieldFormField(field: _field('region', 'text', mandatory: true), initialValue: null, onChanged: (_) {}),
          ),
        ),
      ),
    );

    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('region is required.'), findsOneWidget);
  });

  testWidgets('the mandatory marker shows in the label', (tester) async {
    await _pump(tester, _field('region', 'text', mandatory: true), onChanged: (_) {});
    expect(find.text('region *'), findsOneWidget);
  });

  testWidgets('a readonly text field is disabled', (tester) async {
    await _pump(tester, _field('score', 'text', readonly: true), initial: 'x', onChanged: (_) {});
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.enabled, isFalse);
  });
}
