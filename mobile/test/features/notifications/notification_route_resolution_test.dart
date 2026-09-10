import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notifications/presentation/screens/notification_list_screen.dart';

import 'fake_notification_repository.dart';

void main() {
  group('resolveNotificationRoute', () {
    test('resolves a lead notification to the lead detail route', () {
      final route = resolveNotificationRoute(testNotification(relatedEntityType: 'lead', relatedEntityId: 'lead-1'));
      expect(route, '/app/leads/lead-1');
    });

    test('resolves a follow_up notification to the follow-up detail route', () {
      final route = resolveNotificationRoute(testNotification(relatedEntityType: 'follow_up', relatedEntityId: 'fu-1'));
      expect(route, '/app/follow-ups/fu-1');
    });

    test('resolves a call notification to the call detail route', () {
      final route = resolveNotificationRoute(testNotification(relatedEntityType: 'call', relatedEntityId: 'call-1'));
      expect(route, '/app/calls/call-1');
    });

    test('resolves a customer notification to the customer detail route', () {
      final route = resolveNotificationRoute(testNotification(relatedEntityType: 'customer', relatedEntityId: 'cust-1'));
      expect(route, '/app/customers/cust-1');
    });

    test('returns null for an unrecognized entity type', () {
      final route = resolveNotificationRoute(testNotification(relatedEntityType: 'workspace', relatedEntityId: 'w1'));
      expect(route, isNull);
    });

    test('returns null when there is no related entity at all', () {
      final route = resolveNotificationRoute(testNotification(relatedEntityType: null, relatedEntityId: null));
      expect(route, isNull);
    });

    test('returns null when the type is set but the id is missing', () {
      final route = resolveNotificationRoute(testNotification(relatedEntityType: 'lead', relatedEntityId: null));
      expect(route, isNull);
    });
  });
}
