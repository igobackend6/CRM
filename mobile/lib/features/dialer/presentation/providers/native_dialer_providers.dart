import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/external_url_launcher.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../leads/presentation/providers/leads_providers.dart';
import '../../../sim/presentation/providers/sim_providers.dart';
import '../../data/native_dialer_service.dart';
import '../../domain/native_dialer_models.dart';
import '../../domain/phone_key.dart';

final nativeDialerServiceProvider = Provider<NativeDialerService>((ref) => MethodChannelNativeDialerService());

class DefaultDialerState {
  const DefaultDialerState({this.loaded = false, this.status = const DialerRoleStatus(), this.busy = false, this.message});

  final bool loaded;
  final DialerRoleStatus status;
  final bool busy;

  /// A friendly note for the screen after an action (e.g. the member said no).
  final String? message;

  bool get isDefault => status.isDefault;

  DefaultDialerState copyWith({bool? loaded, DialerRoleStatus? status, bool? busy, String? message, bool clearMessage = false}) =>
      DefaultDialerState(
        loaded: loaded ?? this.loaded,
        status: status ?? this.status,
        busy: busy ?? this.busy,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Settings > Default Dialer. The phone itself is the source of truth for "is the CRM the Phone
/// app" — nothing is stored, so it can never disagree with what the member set in Android.
class DefaultDialerController extends StateNotifier<DefaultDialerState> {
  DefaultDialerController(this._service) : super(const DefaultDialerState());

  final NativeDialerService _service;

  Future<void> refresh() async {
    final status = await _service.status();
    if (mounted) state = state.copyWith(loaded: true, status: status, clearMessage: false);
  }

  /// Asks Android to make the CRM the Phone app (its own system dialog).
  Future<void> turnOn() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    await _service.requestDefaultDialer();
    final status = await _service.status();
    if (!mounted) return;
    state = state.copyWith(
      busy: false,
      loaded: true,
      status: status,
      message: status.isDefault ? null : 'Sales CRM was not set as your Phone app. Calls keep using Google Phone.',
    );
  }

  /// Android has no API to give the role back, so open its Default apps page for the member to pick.
  Future<bool> openDefaultAppsSettings() => _service.openDefaultAppsSettings();
}

final defaultDialerControllerProvider = StateNotifierProvider<DefaultDialerController, DefaultDialerState>(
  (ref) => DefaultDialerController(ref.watch(nativeDialerServiceProvider))..refresh(),
);

/// The SIMs the phone can call on.
final dialerPhoneAccountsProvider = FutureProvider.autoDispose<List<PhoneAccountInfo>>(
  (ref) => ref.watch(nativeDialerServiceProvider).phoneAccounts(),
);

/// The SIM the member picked on the dialer for the next call: null means the business SIM (or Android's default).
final dialerSimChoiceProvider = StateProvider<int?>((ref) => null);

enum CallStartResult { placedByCrm, openedSystemDialer, permissionDenied, invalidNumber, failed }

/// Starts a call from anywhere in the app. With the CRM as the Phone app the call goes through
/// Android's Telecom framework on the right SIM; otherwise it hands the number to the phone's own
/// dialer exactly as before (so turning the CRM dialer off changes nothing else).
class CallPlacer {
  CallPlacer(this._ref);

  final Ref _ref;

  Future<CallStartResult> place(String number, {required ExternalUrlLauncher fallback}) async {
    final clean = number.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (clean.isEmpty) return CallStartResult.invalidNumber;
    final service = _ref.read(nativeDialerServiceProvider);

    final role = await service.status();
    if (!role.isDefault) {
      final opened = await fallback.launch(Uri(scheme: 'tel', path: clean));
      return opened ? CallStartResult.openedSystemDialer : CallStartResult.failed;
    }

    if (!await service.hasCallPermission() && !await service.requestCallPermission()) {
      return CallStartResult.permissionDenied;
    }
    int? subscription = _ref.read(dialerSimChoiceProvider);
    if (subscription == null) {
      try {
        subscription = (await _ref.read(businessSimSelectionProvider.future))?.subscriptionId;
      } catch (_) {
        subscription = null;
      }
    }
    final result = await service.placeCall(clean, subscriptionId: subscription);
    return switch (result) {
      PlaceCallResult.placed => CallStartResult.placedByCrm,
      PlaceCallResult.invalidNumber => CallStartResult.invalidNumber,
      PlaceCallResult.permissionDenied => CallStartResult.permissionDenied,
      _ => CallStartResult.failed,
    };
  }
}

final callPlacerProvider = Provider<CallPlacer>((ref) => CallPlacer(ref));

/// A CRM lead the typed number belongs to.
class LeadMatch {
  const LeadMatch({required this.leadId, required this.name, required this.phone, this.status, this.isCustomer = false});

  final String leadId;
  final String name;
  final String phone;
  final String? status;
  final bool isCustomer;
}

/// Finds the lead whose phone number is [number] (compared on the last 10 digits, so +91 / spaces /
/// a leading 0 don't matter). Null when there is none. The dialer only asks after a short pause and
/// once ten digits are typed.
final leadMatchProvider = FutureProvider.autoDispose.family<LeadMatch?, String>((ref, number) async {
  final key = phoneKey(number);
  if (key == null) return null;
  final context = resolveLeadContext(ref.read);
  if (context == null) return null;
  final repository = ref.watch(leadRepositoryProvider);
  // The server search is a plain substring match on the stored text, which may contain spaces, so
  // try the whole key and then its last five digits (always contiguous), and compare on the key.
  for (final term in [key, key.substring(5)]) {
    try {
      final page = await repository.listLeads(accessToken: context.accessToken, workspaceId: context.workspaceId, search: term, limit: 10);
      for (final lead in page.items) {
        if (phoneKey(lead.phone) == key) {
          return LeadMatch(
            leadId: lead.id,
            name: lead.name,
            phone: lead.phone ?? number,
            status: lead.status?.name,
            isCustomer: lead.isCustomer,
          );
        }
      }
    } catch (e) {
      AppLogger.warning('Looking up a dialled number failed: ${e.runtimeType}');
      return null;
    }
  }
  return null;
});

/// Keeps the phone's small lead list (for the incoming-call screen) up to date. Called when the app
/// opens while the CRM is the Phone app.
Future<void> refreshDialerLeadCache(ProviderReader read) async {
  final context = resolveLeadContext(read);
  if (context == null) return;
  try {
    final page = await read(leadRepositoryProvider).listLeads(accessToken: context.accessToken, workspaceId: context.workspaceId, limit: 100);
    await read(nativeDialerServiceProvider).updateLeadCache([
      for (final lead in page.items)
        if (lead.phone != null && lead.phone!.trim().isNotEmpty) (name: lead.name, phone: lead.phone!, status: lead.status?.name),
    ]);
  } catch (e) {
    AppLogger.warning('Refreshing the dialer lead list failed: ${e.runtimeType}');
  }
}
