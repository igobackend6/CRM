import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI leads surface
/// (`/api/v1/workspaces/{workspace_id}/...` — backend/app/api/v1/leads.py).
/// Kept table-agnostic about domain entities on purpose — converting
/// JSON <-> Lead/Tag/etc. is LeadRepositoryImpl's job (Phase 5 §7's
/// "Repository -> Data Source/API" separation), same split as
/// me_api_data_source.dart.
abstract class LeadApiDataSource {
  Future<Map<String, dynamic>> listLeads({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? statusId,
    // Phase 14 §"Advanced Lead Search, Filters & Saved Views".
    String? sourceId,
    String? assignedMemberId,
    String? priority,
    bool? isCustomer,
    DateTime? createdFrom,
    DateTime? createdTo,
    String? tagId,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> getLead({required String accessToken, required String workspaceId, required String leadId});

  Future<Map<String, dynamic>> createLead({required String accessToken, required String workspaceId, required Map<String, dynamic> body});

  Future<Map<String, dynamic>> updateLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required Map<String, dynamic> body,
  });

  Future<void> deleteLead({required String accessToken, required String workspaceId, required String leadId});

  /// Phase 18 — dedicated Lead -> Customer conversion. No request body:
  /// the server derives everything it needs from the existing lead row
  /// and the authenticated caller.
  Future<Map<String, dynamic>> convertLead({required String accessToken, required String workspaceId, required String leadId});

  Future<List<dynamic>> listStatuses({required String accessToken, required String workspaceId});

  Future<List<dynamic>> listSources({required String accessToken, required String workspaceId});

  Future<List<dynamic>> listTags({required String accessToken, required String workspaceId});

  Future<Map<String, dynamic>> createTag({required String accessToken, required String workspaceId, required Map<String, dynamic> body});

  Future<List<dynamic>> listLeadTags({required String accessToken, required String workspaceId, required String leadId});

  Future<Map<String, dynamic>> attachTag({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String tagId,
  });

  Future<void> detachTag({required String accessToken, required String workspaceId, required String leadId, required String tagId});

  Future<List<dynamic>> listInteractions({required String accessToken, required String workspaceId, required String leadId});

  // ---- assignment (Phase 6) ----

  Future<List<dynamic>> listWorkspaceMembers({required String accessToken, required String workspaceId});

  Future<Map<String, dynamic>> assignLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    String? memberId,
  });

  Future<List<dynamic>> listAllocations({required String accessToken, required String workspaceId, required String leadId});

  // ---- bulk actions & CSV import (Phase 13) ----

  Future<Map<String, dynamic>> bulkAction({
    required String accessToken,
    required String workspaceId,
    required List<String> leadIds,
    required String action,
    String? memberId,
    String? statusId,
  });

  Future<Map<String, dynamic>> importLeads({required String accessToken, required String workspaceId, required String csvContent});

  // ---- unified activity feed & notes (Phase 15) ----

  Future<Map<String, dynamic>> getActivity({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> createNote({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String text,
  });
}

class DioLeadApiDataSource implements LeadApiDataSource {
  DioLeadApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>> listLeads({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? statusId,
    String? sourceId,
    String? assignedMemberId,
    String? priority,
    bool? isCustomer,
    DateTime? createdFrom,
    DateTime? createdTo,
    String? tagId,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'status_id': ?statusId,
          'source_id': ?sourceId,
          'assigned_member_id': ?assignedMemberId,
          'priority': ?priority,
          'is_customer': ?isCustomer,
          'created_from': ?createdFrom?.toIso8601String(),
          'created_to': ?createdTo?.toIso8601String(),
          'tag_id': ?tagId,
          'limit': limit,
          'offset': offset,
        },
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getLead({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('${_base(workspaceId)}/leads/$leadId', options: ApiClient.authOptions(accessToken));
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> createLead({required String accessToken, required String workspaceId, required Map<String, dynamic> body}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads',
        data: body,
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> updateLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId',
        data: body,
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<void> deleteLead({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      await _dio.delete('${_base(workspaceId)}/leads/$leadId', options: ApiClient.authOptions(accessToken));
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> convertLead({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/convert',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listStatuses({required String accessToken, required String workspaceId}) async {
    try {
      final response = await _dio.get<List<dynamic>>('${_base(workspaceId)}/lead-statuses', options: ApiClient.authOptions(accessToken));
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listSources({required String accessToken, required String workspaceId}) async {
    try {
      final response = await _dio.get<List<dynamic>>('${_base(workspaceId)}/lead-sources', options: ApiClient.authOptions(accessToken));
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listTags({required String accessToken, required String workspaceId}) async {
    try {
      final response = await _dio.get<List<dynamic>>('${_base(workspaceId)}/tags', options: ApiClient.authOptions(accessToken));
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> createTag({required String accessToken, required String workspaceId, required Map<String, dynamic> body}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/tags',
        data: body,
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listLeadTags({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      final response = await _dio.get<List<dynamic>>('${_base(workspaceId)}/leads/$leadId/tags', options: ApiClient.authOptions(accessToken));
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> attachTag({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String tagId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/tags',
        data: {'tag_id': tagId},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<void> detachTag({required String accessToken, required String workspaceId, required String leadId, required String tagId}) async {
    try {
      await _dio.delete('${_base(workspaceId)}/leads/$leadId/tags/$tagId', options: ApiClient.authOptions(accessToken));
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listInteractions({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      final response = await _dio.get<List<dynamic>>('${_base(workspaceId)}/leads/$leadId/interactions', options: ApiClient.authOptions(accessToken));
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listWorkspaceMembers({required String accessToken, required String workspaceId}) async {
    try {
      final response = await _dio.get<List<dynamic>>('${_base(workspaceId)}/members', options: ApiClient.authOptions(accessToken));
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> assignLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    String? memberId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/assignment',
        data: {'member_id': memberId},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<List<dynamic>> listAllocations({required String accessToken, required String workspaceId, required String leadId}) async {
    try {
      final response = await _dio.get<List<dynamic>>('${_base(workspaceId)}/leads/$leadId/allocations', options: ApiClient.authOptions(accessToken));
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> bulkAction({
    required String accessToken,
    required String workspaceId,
    required List<String> leadIds,
    required String action,
    String? memberId,
    String? statusId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/bulk',
        data: {
          'lead_ids': leadIds,
          'action': action,
          'member_id': ?memberId,
          'status_id': ?statusId,
        },
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> importLeads({required String accessToken, required String workspaceId, required String csvContent}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/import',
        data: {'csv_content': csvContent},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getActivity({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/activity',
        queryParameters: {'limit': limit, 'offset': offset},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> createNote({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String text,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/notes',
        data: {'text': text},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
