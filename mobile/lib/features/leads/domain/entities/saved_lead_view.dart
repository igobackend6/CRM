import 'lead_filters.dart';

/// Phase 14 §"Saved Views" — a named [LeadFilters] preset, persisted
/// locally only (no backend table; see SavedViewsController). Deliberately
/// this simple: a name and a filter set, not a customizable dashboard.
class SavedLeadView {
  const SavedLeadView({required this.id, required this.name, required this.filters});

  factory SavedLeadView.fromJson(Map<String, dynamic> json) => SavedLeadView(
        id: json['id'] as String,
        name: json['name'] as String,
        filters: LeadFilters.fromJson(json['filters'] as Map<String, dynamic>),
      );

  final String id;
  final String name;
  final LeadFilters filters;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'filters': filters.toJson()};
}
