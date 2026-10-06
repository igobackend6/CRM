import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/widgets/widgets.dart';

void main() {
  testWidgets('the label is dark and bold so it reads clearly, and the value is shown beside it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: DetailInfoRow(label: 'Assigned to', value: 'testing2')),
      ),
    );

    final label = tester.widget<Text>(find.text('Assigned to'));
    expect(label.style?.color, AppColors.textHeading);
    expect(label.style?.fontWeight, FontWeight.w700);
    expect(find.text('testing2'), findsOneWidget);
  });
}
