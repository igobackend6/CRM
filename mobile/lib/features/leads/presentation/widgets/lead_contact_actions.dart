import '../../../dialer/presentation/providers/native_dialer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../call_outcome/domain/pending_call_outcome.dart';
import '../../../call_outcome/presentation/providers/call_outcome_providers.dart';
import '../../../whatsapp/domain/phone_number_normalizer.dart';
import '../providers/leads_providers.dart';

/// Two one-tap contact buttons for a lead, shown beside the name:
///
/// * **Call** — opens the phone's normal dialer with the number already filled in (the user
///   presses the dialer's own call button).
/// * **WhatsApp call** — opens WhatsApp on that number. WhatsApp has no public link that starts a
///   voice call by itself, so this lands on the chat, where its call button is one tap away.
///
/// Both are disabled when the lead has no phone number.
class LeadContactActions extends ConsumerWidget {
  const LeadContactActions({
    super.key,
    required this.phone,
    this.leadId,
    this.leadName,
    this.isCustomer = false,
    this.compact = false,
  });

  final String? phone;

  /// Which lead the call is for. When set, starting a call marks it as awaiting a result, and the
  /// after-call pop-up opens when the member returns to the app.
  final String? leadId;
  final String? leadName;

  /// Whether that lead is already a customer — Settings > Enable Note Dialog can limit the pop-up to leads.
  final bool isCustomer;

  /// Smaller buttons for list rows (the detail header uses the full size).
  final bool compact;

  bool get _hasPhone => phone != null && phone!.trim().isNotEmpty;

  /// Marked before the dialer / WhatsApp opens (not after): the app is backgrounded the instant they open.
  void _expectOutcome(WidgetRef ref) {
    final id = leadId;
    if (id == null) return;
    ref.read(pendingCallOutcomeProvider.notifier).state = PendingCallOutcome(leadId: id, leadName: leadName ?? '', isCustomer: isCustomer);
  }

  void _cancelOutcome(WidgetRef ref) {
    if (leadId != null) ref.read(pendingCallOutcomeProvider.notifier).state = null;
  }

  Future<void> _dial(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // Keep digits and a leading + only: spaces and dashes are not valid in a tel: link.
    final number = phone!.replaceAll(RegExp(r'[^0-9+]'), '');
    _expectOutcome(ref);
    // With the CRM as the Phone app this places the call itself; otherwise it opens the phone's dialer as before.
    final result = await ref.read(callPlacerProvider).place(number, fallback: ref.read(leadContactLauncherProvider));
    if (result == CallStartResult.permissionDenied) {
      _cancelOutcome(ref);
      messenger.showSnackBar(const SnackBar(content: Text('Allow the Phone permission to place calls from Sales CRM.')));
    } else if (result == CallStartResult.failed || result == CallStartResult.invalidNumber) {
      _cancelOutcome(ref);
      messenger.showSnackBar(const SnackBar(content: Text('Could not open the phone dialer.')));
    }
  }

  Future<void> _openWhatsApp(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final normalized = normalizePhoneForWhatsApp(phone, defaultCountryCode: AppConstants.defaultPhoneCountryCode);
    if (!normalized.isValid) {
      messenger.showSnackBar(const SnackBar(content: Text('This number cannot be opened in WhatsApp. Save it with its country code, e.g. +91…')));
      return;
    }
    _expectOutcome(ref);
    final opened = await ref.read(leadContactLauncherProvider).launch(Uri.https('wa.me', '/${normalized.internationalDigits}'));
    if (!opened) {
      _cancelOutcome(ref);
      messenger.showSnackBar(const SnackBar(content: Text('Could not open WhatsApp. Is it installed?')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundAction(
          key: const Key('lead-call-button'),
          tooltip: 'Call',
          size: compact ? 34 : 40,
          background: AppColors.accentBg,
          onPressed: _hasPhone ? () => _dial(context, ref) : null,
          child: Icon(Icons.call, size: compact ? 17 : 20, color: AppColors.accent),
        ),
        SizedBox(width: compact ? 6 : 8),
        _RoundAction(
          key: const Key('lead-whatsapp-call-button'),
          tooltip: 'WhatsApp call',
          size: compact ? 34 : 40,
          background: AppColors.successBg,
          onPressed: _hasPhone ? () => _openWhatsApp(context, ref) : null,
          child: _WhatsAppCallGlyph(size: compact ? 19 : 22),
        ),
      ],
    );
  }
}

/// The right end of a lead/customer list row's name line: the compact call / WhatsApp-call buttons,
/// then the status chip (if any). Shared by the Allocations and Customers lists.
class LeadRowTrailing extends StatelessWidget {
  const LeadRowTrailing({super.key, required this.phone, required this.chip, this.leadId, this.leadName, this.isCustomer = false});

  final String? phone;
  final Widget? chip;
  final String? leadId;
  final String? leadName;
  final bool isCustomer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LeadContactActions(phone: phone, leadId: leadId, leadName: leadName, isCustomer: isCustomer, compact: true),
        if (chip != null) ...[const SizedBox(width: 8), chip!],
      ],
    );
  }
}

/// A green chat bubble with a phone in it: reads as "call on WhatsApp" without the WhatsApp logo
/// (Material icons have none).
class _WhatsAppCallGlyph extends StatelessWidget {
  const _WhatsAppCallGlyph({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.chat_bubble, size: size, color: AppColors.success),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Icon(Icons.call, size: size / 2, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({super.key, required this.tooltip, required this.size, required this.background, required this.onPressed, required this.child});

  final String tooltip;
  final double size;
  final Color background;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(width: size, height: size, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
