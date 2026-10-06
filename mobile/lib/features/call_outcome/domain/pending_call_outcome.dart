/// A call the member just started from a lead (a normal call or a WhatsApp call) and has not yet
/// recorded the result of. Kept until they come back to the app and submit the pop-up.
class PendingCallOutcome {
  const PendingCallOutcome({required this.leadId, required this.leadName, this.isCustomer = false});

  final String leadId;
  final String leadName;

  /// Whether the lead is already a customer. Settings > Enable Note Dialog can limit the pop-up to leads.
  final bool isCustomer;
}
