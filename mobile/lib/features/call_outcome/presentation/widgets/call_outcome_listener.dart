import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../domain/pending_call_outcome.dart';
import '../providers/call_outcome_providers.dart';
import 'call_outcome_dialog.dart';

/// Wraps the whole app. When the member comes back from a call they started from a lead (the dialer or
/// WhatsApp took over the screen, then they returned), it opens the call-summary pop-up straight away,
/// over whatever screen they land on, so the result is recorded before anything else.
///
/// It only fires when the app really went to the background after the call was started, so opening the
/// pop-up never happens the instant the button is tapped.
class CallOutcomeListener extends ConsumerStatefulWidget {
  const CallOutcomeListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CallOutcomeListener> createState() => _CallOutcomeListenerState();
}

class _CallOutcomeListenerState extends ConsumerState<CallOutcomeListener> with WidgetsBindingObserver {
  bool _leftApp = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final pending = ref.read(pendingCallOutcomeProvider);
    if (pending == null) return;
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.hidden) {
      _leftApp = true;
    } else if (lifecycle == AppLifecycleState.resumed && _leftApp) {
      _leftApp = false;
      // Settings > Enable Note Dialog: skip the pop-up (and forget the call) when the member turned it
      // off, or limited it to leads and this one is already a customer.
      final mode = ref.read(appSettingsControllerProvider).noteDialogMode;
      final skip = mode == NoteDialogMode.never || (mode == NoteDialogMode.onlyForLeads && pending.isCustomer);
      if (skip) {
        ref.read(pendingCallOutcomeProvider.notifier).state = null;
        return;
      }
      _show(pending);
    }
  }

  Future<void> _show(PendingCallOutcome pending) async {
    if (_showing) return;
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) return;
    _showing = true;
    try {
      await showDialog<void>(
        context: navigatorContext,
        barrierDismissible: false,
        builder: (_) => CallOutcomeDialog(leadId: pending.leadId, leadName: pending.leadName),
      );
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // A new call replaces the previous one: start counting "left the app" afresh.
    ref.listen<PendingCallOutcome?>(pendingCallOutcomeProvider, (previous, next) {
      if (next != null && next != previous) _leftApp = false;
    });
    return widget.child;
  }
}
