import 'device_call.dart';

/// A phone call that the server accepted as belonging to a lead (see SyncedCall), with what the
/// phone knows about it.
class SyncedDeviceCall {
  const SyncedDeviceCall({required this.callId, required this.leadId, required this.call});

  final String callId;
  final String leadId;
  final DeviceCall call;
}

/// One lead who needs a call back, and the call that is the reason.
class LeadCallBack {
  const LeadCallBack({required this.leadId, required this.latest, required this.callIds});

  final String leadId;

  /// The lead's most recent unattended call — the one the reminder talks about.
  final SyncedDeviceCall latest;

  /// All of this lead's unattended calls covered by this one reminder (so none triggers another).
  final Set<String> callIds;
}

/// What "Never Attended Call Reminder" should do after a sync.
class CallBackPlan {
  const CallBackPlan({required this.callBacks, required this.answeredLeadIds, required this.consideredCallIds});

  /// Leads to remind about: their latest call went unanswered and nothing after it connected.
  final List<LeadCallBack> callBacks;

  /// Leads who connected in this batch with nothing unanswered after it (they were called back, or
  /// called) — any pending call-back alert for them is no longer needed.
  final Set<String> answeredLeadIds;

  /// Every unattended call looked at, whatever the outcome, so it is never judged twice.
  final Set<String> consideredCallIds;
}

/// Decides which leads need a call-back reminder.
///
/// "Never attended" covers the three ways a call goes unanswered: an incoming call that was missed,
/// an incoming call that was rejected, and an outgoing call nobody picked up. A lead needs a
/// reminder when its most recent such call has nothing connected after it. Only calls from
/// [sinceMillis] (when the member turned the reminder on) and not in [handled] are considered, so
/// turning it on never floods the member with the past week's missed calls.
CallBackPlan planCallBacks({
  required List<SyncedDeviceCall> calls,
  required int sinceMillis,
  required Set<String> handled,
  int maxLeads = 20,
}) {
  final byLead = <String, List<SyncedDeviceCall>>{};
  for (final c in calls) {
    byLead.putIfAbsent(c.leadId, () => []).add(c);
  }

  final callBacks = <LeadCallBack>[];
  final answered = <String>{};
  final considered = <String>{};

  for (final entry in byLead.entries) {
    final lead = entry.value..sort((a, b) => a.call.dateMillis.compareTo(b.call.dateMillis));
    if (lead.any((c) => c.call.isConnected)) answered.add(entry.key);
    final fresh = [
      for (final c in lead)
        if (c.call.isUnattended && c.call.dateMillis >= sinceMillis && !handled.contains(c.callId)) c,
    ];
    if (fresh.isEmpty) continue;
    considered.addAll(fresh.map((c) => c.callId));

    final latest = fresh.last;
    final connectedAfter = lead.any((c) => c.call.isConnected && c.call.dateMillis > latest.call.dateMillis);
    if (connectedAfter) continue;
    callBacks.add(LeadCallBack(leadId: entry.key, latest: latest, callIds: fresh.map((c) => c.callId).toSet()));
  }

  // A lead that still gets a reminder (its unattended call is the latest) is not "answered".
  answered.removeAll(callBacks.map((c) => c.leadId));

  // The most recent first, if there are more than we want to create in one go.
  callBacks.sort((a, b) => b.latest.call.dateMillis.compareTo(a.latest.call.dateMillis));
  if (callBacks.length > maxLeads) {
    // The ones left out stay unhandled, so the next sync picks them up.
    for (final dropped in callBacks.sublist(maxLeads)) {
      considered.removeAll(dropped.callIds);
    }
    callBacks.removeRange(maxLeads, callBacks.length);
  }
  return CallBackPlan(callBacks: callBacks, answeredLeadIds: answered, consideredCallIds: considered);
}
