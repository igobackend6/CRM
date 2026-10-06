import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/business_sim_selection.dart';
import '../domain/sim_card.dart';
import '../domain/sim_permission_status.dart';
import 'sim_platform_source.dart';
import 'sim_selection_storage.dart';

enum SimReadFailure { permissionDenied, unavailable, readFailed }

class SimReadException implements Exception {
  const SimReadException(this.failure);

  final SimReadFailure failure;

  @override
  String toString() => 'SimReadException(${failure.name})';
}

/// Connected SIM Details' single entry point: detects the phone's SIMs and keeps the employee's
/// business-SIM choice. Entirely on the phone — no server call, so it works offline.
///
/// Saved shape, per employee who signs in on this install (so a shared phone never mixes them up):
/// ```
/// {"installId": "<random>",
///  "selections": {"<profile id>": {...}},
///  "numbers": {"<profile id>": {"<subscription id>": "+91..."}}}
/// ```
class SimRepository {
  SimRepository(this._source, this._storage, {Random? random, DateTime Function()? clock})
      : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final SimPlatformSource _source;
  final SimSelectionStorage _storage;
  final Random _random;
  final DateTime Function() _clock;

  static const _detectTimeout = Duration(seconds: 10);

  Future<SimPermissionStatus> permissionStatus() async {
    try {
      return SimPermissionStatus.fromPlatform(await _source.permissionStatus());
    } on MissingPluginException {
      return SimPermissionStatus.unavailable;
    } catch (e) {
      AppLogger.warning('SIM permission check failed: ${_code(e)}');
      return SimPermissionStatus.denied;
    }
  }

  Future<SimPermissionStatus> requestPermission() async {
    try {
      return SimPermissionStatus.fromPlatform(await _source.requestPermission());
    } on MissingPluginException {
      return SimPermissionStatus.unavailable;
    } catch (e) {
      AppLogger.warning('SIM permission request failed: ${_code(e)}');
      return permissionStatus();
    }
  }

  /// The active subscriptions, ordered by slot. Throws [SimReadException].
  Future<List<SimCard>> detectActiveSims() async {
    try {
      final raw = await _source.activeSubscriptions().timeout(_detectTimeout);
      final sims = simsFromPlatform(raw);
      // Count only — never the numbers or carrier details.
      AppLogger.info('SIM detection: ${sims.length} active subscription(s)');
      return sims;
    } on PlatformException catch (e) {
      AppLogger.warning('SIM detection failed: ${e.code}');
      throw SimReadException(switch (e.code) {
        'permission_denied' => SimReadFailure.permissionDenied,
        'unavailable' => SimReadFailure.unavailable,
        _ => SimReadFailure.readFailed,
      });
    } on MissingPluginException {
      throw const SimReadException(SimReadFailure.unavailable);
    } catch (e) {
      AppLogger.warning('SIM detection failed: ${_code(e)}');
      throw const SimReadException(SimReadFailure.readFailed);
    }
  }

  Future<BusinessSimSelection?> loadSelection(String profileId) async {
    final doc = await _readDoc();
    final selections = doc['selections'];
    return selections is Map ? BusinessSimSelection.fromJson(selections[profileId]) : null;
  }

  /// Makes [sim] this employee's business SIM. Replaces only this employee's previous choice.
  Future<BusinessSimSelection> select(String profileId, SimCard sim) async {
    final doc = await _readDoc();
    var installId = doc['installId'];
    if (installId is! String || installId.isEmpty) {
      installId = _newInstallId();
      doc['installId'] = installId;
    }
    final selection = BusinessSimSelection.fromSim(sim, deviceInstallId: installId, selectedAt: _clock());
    final selections = doc['selections'] is Map ? Map<String, Object?>.from(doc['selections'] as Map) : <String, Object?>{};
    selections[profileId] = selection.toJson();
    doc['selections'] = selections;
    await _storage.write(jsonEncode(doc));
    return selection;
  }

  /// This install's random ID (created on first use). Prefixes synced calls' device keys so the
  /// same phone call is never imported twice.
  Future<String> installId() async {
    final doc = await _readDoc();
    final existing = doc['installId'];
    if (existing is String && existing.isNotEmpty) return existing;
    final id = _newInstallId();
    doc['installId'] = id;
    await _storage.write(jsonEncode(doc));
    return id;
  }

  /// The mobile numbers this employee entered for their SIMs, keyed by subscription ID.
  Future<Map<int, String>> loadNumbers(String profileId) async {
    final doc = await _readDoc();
    final all = doc['numbers'];
    final mine = all is Map ? all[profileId] : null;
    if (mine is! Map) return const {};
    final numbers = <int, String>{};
    mine.forEach((key, value) {
      final id = int.tryParse(key.toString());
      if (id != null && value is String && value.isNotEmpty) numbers[id] = value;
    });
    return numbers;
  }

  /// Saves the (already validated) number this employee entered for the SIM [subscriptionId].
  /// Kept only on this phone; never logged.
  Future<void> saveNumber(String profileId, int subscriptionId, String number) async {
    final doc = await _readDoc();
    final all = doc['numbers'] is Map ? Map<String, Object?>.from(doc['numbers'] as Map) : <String, Object?>{};
    final mine = all[profileId] is Map ? Map<String, Object?>.from(all[profileId] as Map) : <String, Object?>{};
    mine['$subscriptionId'] = number;
    all[profileId] = mine;
    doc['numbers'] = all;
    await _storage.write(jsonEncode(doc));
  }

  Future<bool> openAppSettings() async {
    try {
      return await _source.openAppSettings();
    } catch (e) {
      AppLogger.warning('Opening app settings failed: ${_code(e)}');
      return false;
    }
  }

  Future<Map<String, Object?>> _readDoc() async {
    final raw = await _storage.read();
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : <String, Object?>{};
    } on FormatException {
      AppLogger.warning('Saved SIM selection was unreadable; starting fresh');
      return <String, Object?>{};
    }
  }

  String _newInstallId() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static String _code(Object e) => e is PlatformException ? e.code : e.runtimeType.toString();

  /// Maps the bridge's answer to [SimCard]s: skips anything without a usable subscription ID,
  /// keeps the first of any duplicate, and orders by slot (unknown slot last).
  static List<SimCard> simsFromPlatform(Object? raw) {
    if (raw is! List) return const [];
    final byId = <int, SimCard>{};
    for (final entry in raw) {
      final sim = simFromPlatform(entry);
      if (sim != null) byId.putIfAbsent(sim.subscriptionId, () => sim);
    }
    final sims = byId.values.toList()
      ..sort((a, b) {
        final sa = a.slotIndex, sb = b.slotIndex;
        if (sa == null && sb == null) return a.subscriptionId.compareTo(b.subscriptionId);
        if (sa == null) return 1;
        if (sb == null) return -1;
        return sa.compareTo(sb);
      });
    return sims;
  }

  static SimCard? simFromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['subscriptionId'];
    // Android's invalid subscription ID is -1.
    if (id is! int || id < 0) return null;
    final slot = raw['slotIndex'];
    final active = raw['isActive'];
    return SimCard(
      subscriptionId: id,
      slotIndex: slot is int && slot >= 0 ? slot : null,
      carrierName: _text(raw['carrierName']),
      displayName: _text(raw['displayName']),
      phoneNumber: _text(raw['phoneNumber']),
      simState: _text(raw['simState']),
      isActive: active is bool ? active : true,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
