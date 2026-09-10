/// Common contract every WhatsApp "provider" implements (§8's
/// architecture: `WhatsAppMessageService -> WhatsAppDeepLinkProvider ->
/// Future WhatsAppBusinessProvider`). Today [DeepLinkWhatsAppProvider]
/// (data/deep_link_whatsapp_provider.dart) is the only implementation —
/// a manual `wa.me` link the user confirms and WhatsApp itself sends.
/// A future WhatsAppBusinessProvider (real API-based, automated
/// sending) would implement this exact interface, so
/// WhatsAppMessageService and everything above it never has to change
/// to support it — this phase deliberately does NOT build that
/// provider or wire any Business API credential (§6 "Do NOT implement
/// WhatsApp Business API... automatic sending... campaign automation").
abstract class WhatsAppProvider {
  /// Returns true if the send was actually handed off (WhatsApp opened
  /// / the API accepted it) — never true for a phone/message that was
  /// never actually dispatched anywhere.
  Future<bool> send({required String internationalPhoneDigits, required String message});
}
