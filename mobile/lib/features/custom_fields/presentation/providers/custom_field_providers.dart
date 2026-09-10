import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../../../services/api/custom_field_api_data_source.dart';
import '../../data/custom_field_repository_impl.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/repositories/custom_field_repository.dart';

final customFieldApiDataSourceProvider =
    Provider<CustomFieldApiDataSource>((ref) => DioCustomFieldApiDataSource());

final customFieldRepositoryProvider = Provider<CustomFieldRepository>(
  (ref) => CustomFieldRepositoryImpl(ref.watch(customFieldApiDataSourceProvider)),
);

/// The workspace's custom lead-field definitions. Cached for as long as
/// something watches it (plus the autoDispose grace window), so opening
/// the lead form repeatedly in one session doesn't re-fetch. Returns an
/// empty list — not an error — when the workspace defines no custom
/// fields, which is the common case.
final workspaceCustomFieldsProvider = FutureProvider.autoDispose<List<CustomField>>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(customFieldRepositoryProvider);
  return repository.listFields(accessToken: user.accessToken, workspaceId: workspace.workspace.id);
});
