import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leads/domain/entities/lead_filters.dart';
import 'package:mobile/features/leads/presentation/controllers/saved_views_controller.dart';

import '../../helpers/wait_until.dart';
import 'fake_lead_filter_storage.dart';

void main() {
  group('SavedViewsController', () {
    test('starts empty when nothing has been persisted yet', () async {
      final controller = SavedViewsController(FakeLeadFilterStorage());
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero); // let the constructor's async _load() settle
      expect(controller.state, isEmpty);
    });

    test('save appends a named view and persists it', () async {
      final storage = FakeLeadFilterStorage();
      final controller = SavedViewsController(storage);
      addTearDown(controller.dispose);

      await controller.save('Hot leads', const LeadFilters(priority: 'urgent'));

      expect(controller.state, hasLength(1));
      expect(controller.state.single.name, 'Hot leads');
      expect(controller.state.single.filters.priority, 'urgent');
      expect(storage.stored, isNotNull);
    });

    test('save with a blank name is a no-op', () async {
      final controller = SavedViewsController(FakeLeadFilterStorage());
      addTearDown(controller.dispose);

      await controller.save('   ', const LeadFilters(priority: 'urgent'));

      expect(controller.state, isEmpty);
    });

    test('delete removes a saved view and persists the change', () async {
      final storage = FakeLeadFilterStorage();
      final controller = SavedViewsController(storage);
      addTearDown(controller.dispose);
      await controller.save('Hot leads', const LeadFilters(priority: 'urgent'));
      final id = controller.state.single.id;

      await controller.delete(id);

      expect(controller.state, isEmpty);
      expect(storage.stored, '[]');
    });

    test('a saved view persisted earlier is loaded back on construction', () async {
      final storage = FakeLeadFilterStorage();
      final seed = SavedViewsController(storage);
      addTearDown(seed.dispose);
      await seed.save('Hot leads', const LeadFilters(priority: 'urgent', tagId: 't1'));

      final reloaded = SavedViewsController(storage);
      addTearDown(reloaded.dispose);
      await waitUntil(() => reloaded.state.isNotEmpty);

      expect(reloaded.state.single.name, 'Hot leads');
      expect(reloaded.state.single.filters.tagId, 't1');
    });

    test('corrupt persisted data is treated as no saved views rather than crashing', () async {
      final storage = FakeLeadFilterStorage()..stored = 'not valid json';

      final controller = SavedViewsController(storage);
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isEmpty);
    });
  });
}
