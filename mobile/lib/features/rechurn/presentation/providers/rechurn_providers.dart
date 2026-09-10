import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/rechurn_api_data_source.dart';
import '../../../pipeline/presentation/providers/pipeline_providers.dart';
import '../../data/rechurn_repository_impl.dart';
import '../../domain/entities/rechurn_list_state.dart';
import '../../domain/repositories/rechurn_repository.dart';
import '../controllers/rechurn_list_controller.dart';

final rechurnApiDataSourceProvider = Provider<RechurnApiDataSource>((ref) => DioRechurnApiDataSource());

final rechurnRepositoryProvider = Provider<RechurnRepository>((ref) {
  return RechurnRepositoryImpl(ref.watch(rechurnApiDataSourceProvider));
});

final rechurnListControllerProvider = StateNotifierProvider.autoDispose<RechurnListController, RechurnListState>((ref) {
  // Reuses PipelineRepository (Phase 12) for the queue's inline
  // status-change action — no second implementation of that write path.
  return RechurnListController(ref.watch(rechurnRepositoryProvider), ref.watch(pipelineRepositoryProvider), ref);
});
