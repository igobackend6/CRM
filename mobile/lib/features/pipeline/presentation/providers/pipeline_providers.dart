import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/pipeline_api_data_source.dart';
import '../../data/pipeline_repository_impl.dart';
import '../../domain/entities/pipeline_state.dart';
import '../../domain/repositories/pipeline_repository.dart';
import '../controllers/pipeline_controller.dart';

final pipelineApiDataSourceProvider = Provider<PipelineApiDataSource>((ref) => DioPipelineApiDataSource());

final pipelineRepositoryProvider = Provider<PipelineRepository>((ref) {
  return PipelineRepositoryImpl(ref.watch(pipelineApiDataSourceProvider));
});

final pipelineControllerProvider = StateNotifierProvider.autoDispose<PipelineController, PipelineState>((ref) {
  return PipelineController(ref.watch(pipelineRepositoryProvider), ref);
});
