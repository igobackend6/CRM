import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/onboarding/domain/onboarding_page_data.dart';
import 'package:mobile/features/onboarding/domain/onboarding_status.dart';
import 'package:mobile/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:mobile/features/onboarding/presentation/screens/onboarding_screen.dart';

import 'fake_onboarding_storage.dart';

Future<ProviderContainer> _pump(WidgetTester tester, FakeOnboardingStorage storage) async {
  final container = ProviderContainer(overrides: [onboardingStorageProvider.overrideWithValue(storage)]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MaterialApp(home: OnboardingScreen())),
  );
  await tester.pump();
  return container;
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Next'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('shows the first slide with a Skip button and no Get Started yet', (tester) async {
    await _pump(tester, FakeOnboardingStorage());

    expect(find.text(onboardingPages.first.title), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.bySemanticsLabel('Next'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);
  });

  testWidgets('walking through every slide ends on Get Started, which completes onboarding', (tester) async {
    final storage = FakeOnboardingStorage();
    final container = await _pump(tester, storage);

    for (var i = 1; i < onboardingPages.length; i++) {
      await _tapNext(tester);
      expect(find.text(onboardingPages[i].title), findsOneWidget);
    }

    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pump();

    expect(container.read(onboardingControllerProvider), OnboardingStatus.seen);
    expect(storage.seen, isTrue);
  });

  testWidgets('Skip completes onboarding straight away', (tester) async {
    final storage = FakeOnboardingStorage();
    final container = await _pump(tester, storage);

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(container.read(onboardingControllerProvider), OnboardingStatus.seen);
    expect(storage.seen, isTrue);
  });

  testWidgets('each of the five slides plays its animation without errors', (tester) async {
    await _pump(tester, FakeOnboardingStorage());

    for (var i = 1; i < onboardingPages.length; i++) {
      await _tapNext(tester);
      // Let the intro finish and part of the ambient loop run.
      await tester.pump(const Duration(milliseconds: 1800));
      final error = tester.takeException();
      expect(error, isNull, reason: 'slide ${onboardingPages[i].title}: $error');
    }
  });

  testWidgets('works with animations disabled (accessibility setting)', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pump(tester, FakeOnboardingStorage());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(onboardingPages.first.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
