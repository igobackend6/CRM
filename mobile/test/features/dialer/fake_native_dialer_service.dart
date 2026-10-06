import 'dart:async';

import 'package:mobile/features/dialer/data/native_dialer_service.dart';
import 'package:mobile/features/dialer/domain/native_dialer_models.dart';

class FakeNativeDialerService implements NativeDialerService {
  FakeNativeDialerService({
    this.isDefault = false,
    this.available = true,
    this.grantsRole = true,
    this.callPermission = true,
    this.grantsCallPermission = true,
    List<PhoneAccountInfo>? accounts,
  }) : accounts = accounts ?? [];

  bool isDefault;
  bool available;

  /// Whether the system "set as default" dialog is accepted.
  bool grantsRole;
  bool callPermission;
  bool grantsCallPermission;
  List<PhoneAccountInfo> accounts;
  PlaceCallResult placeResult = PlaceCallResult.placed;
  String? dialNumber;

  int roleRequests = 0;
  int settingsOpens = 0;
  int permissionRequests = 0;
  final List<({String number, int? subscriptionId})> placed = [];
  List<({String name, String phone, String? status})> leadCache = [];

  final _events = StreamController<NativeCallEvent>.broadcast();

  void emit(NativeCallEvent event) => _events.add(event);

  @override
  Future<DialerRoleStatus> status() async => DialerRoleStatus(isDefault: isDefault, available: available);

  @override
  Future<bool> requestDefaultDialer() async {
    roleRequests++;
    if (grantsRole) isDefault = true;
    return isDefault;
  }

  @override
  Future<bool> openDefaultAppsSettings() async {
    settingsOpens++;
    return true;
  }

  @override
  Future<List<PhoneAccountInfo>> phoneAccounts() async => accounts;

  @override
  Future<bool> hasCallPermission() async => callPermission;

  @override
  Future<bool> requestCallPermission() async {
    permissionRequests++;
    if (grantsCallPermission) callPermission = true;
    return callPermission;
  }

  @override
  Future<PlaceCallResult> placeCall(String number, {int? subscriptionId}) async {
    placed.add((number: number, subscriptionId: subscriptionId));
    return placeResult;
  }

  @override
  Future<void> updateLeadCache(List<({String name, String phone, String? status})> leads) async => leadCache = leads;

  @override
  Future<String?> takeDialNumber() async {
    final n = dialNumber;
    dialNumber = null;
    return n;
  }

  @override
  Stream<NativeCallEvent> get callEvents => _events.stream;
}
