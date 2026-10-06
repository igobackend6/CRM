import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/widgets/widgets.dart';

Widget _app({required Widget home}) => MaterialApp(theme: AppTheme.light, home: home);

void main() {
  group('AppBottomNavBar', () {
    Future<List<AppNavTab>> pumpBar(WidgetTester tester, {AppNavTab current = AppNavTab.home}) async {
      final tapped = <AppNavTab>[];
      await tester.pumpWidget(
        _app(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(currentTab: current, onSelect: tapped.add),
            floatingActionButton: AppCallFab(onPressed: () {}),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          ),
        ),
      );
      return tapped;
    }

    testWidgets('lays out without overflow and shows all four tabs', (tester) async {
      // An overflow would be reported as a test exception.
      await pumpBar(tester);

      for (final label in ['Home', 'Allocations', 'Customers', 'Menu']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('the bar is brand blue', (tester) async {
      await pumpBar(tester);

      final bar = tester.widget<BottomAppBar>(find.byType(BottomAppBar));
      expect(bar.color, AppColors.accent);
    });

    testWidgets('the selected tab is full white, the others soft white', (tester) async {
      await pumpBar(tester, current: AppNavTab.allocations);

      Color? colorOf(String label) => tester.widget<Text>(find.text(label)).style?.color;
      expect(colorOf('Allocations'), Colors.white);
      expect(colorOf('Home'), Colors.white.withValues(alpha: 0.7));
    });

    testWidgets('tapping a tab reports it', (tester) async {
      final tapped = await pumpBar(tester);

      await tester.tap(find.text('Customers'));
      await tester.tap(find.text('Menu'));

      expect(tapped, [AppNavTab.customers, AppNavTab.menu]);
    });

    testWidgets('the call button is white with a blue phone, so it stands out on the blue bar', (tester) async {
      await pumpBar(tester);

      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.backgroundColor, Colors.white);
      expect(fab.foregroundColor, AppColors.accent);
    });
  });

  group('brandAppBar', () {
    testWidgets('paints the brand gradient and shows a white title and icons', (tester) async {
      await tester.pumpWidget(
        _app(
          home: Scaffold(
            appBar: brandAppBar(
              title: const Text('Reports'),
              actions: [IconButton(icon: const Icon(Icons.search), onPressed: () {})],
            ),
          ),
        ),
      );

      final decorated = tester.widgetList<DecoratedBox>(find.descendant(of: find.byType(AppBar), matching: find.byType(DecoratedBox)));
      final gradient = decorated.map((d) => d.decoration).whereType<BoxDecoration>().map((d) => d.gradient).whereType<LinearGradient>().single;
      expect(gradient.colors, AppColors.gradientBrand);

      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, kBrandAppBarHeight);
      expect(DefaultTextStyle.of(tester.element(find.text('Reports'))).style.color, Colors.white);
      expect(IconTheme.of(tester.element(find.byIcon(Icons.search))).color, Colors.white);
    });

    testWidgets('a plain AppBar in the theme is still white-on-blue', (tester) async {
      await tester.pumpWidget(_app(home: Scaffold(appBar: AppBar(title: const Text('Plain')))));

      final theme = AppTheme.light.appBarTheme;
      expect(theme.backgroundColor, AppColors.accent);
      expect(theme.foregroundColor, Colors.white);
    });
  });
}
