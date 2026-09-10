import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/lead_filters.dart';
import '../../domain/entities/saved_lead_view.dart';
import 'lead_filter_storage.dart';

/// Phase 14 §"Saved Views" — simple named filter presets. Persisted
/// entirely on-device (no new backend table, per §"Prefer NO MIGRATION"),
/// as one JSON blob under a single storage key; the list is expected to
/// stay small (a handful of presets per rep), so every save/delete just
/// re-persists the whole list rather than anything more elaborate.
class SavedViewsController extends StateNotifier<List<SavedLeadView>> {
  SavedViewsController(this._storage) : super(const []) {
    _load();
  }

  final LeadFilterStorage _storage;

  Future<void> _load() async {
    final raw = await _storage.readSavedViews();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(SavedLeadView.fromJson).toList();
      state = decoded;
    } catch (_) {
      // Corrupt/foreign data under this key — treat as "no saved views"
      // rather than crashing the Lead List screen over it.
      state = const [];
    }
  }

  Future<void> save(String name, LeadFilters filters) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final view = SavedLeadView(id: DateTime.now().microsecondsSinceEpoch.toString(), name: trimmed, filters: filters);
    state = [...state, view];
    await _persist();
  }

  Future<void> delete(String id) async {
    state = state.where((v) => v.id != id).toList();
    await _persist();
  }

  Future<void> _persist() {
    return _storage.writeSavedViews(jsonEncode(state.map((v) => v.toJson()).toList()));
  }
}
