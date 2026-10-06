import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/pending_call_outcome.dart';

/// The call the member started and still owes a result for. Set the moment a Call / WhatsApp-call button
/// opens the dialer (or WhatsApp); cleared when the after-call pop-up is submitted.
final pendingCallOutcomeProvider = StateProvider<PendingCallOutcome?>((ref) => null);

/// The root navigator, so the pop-up can open over whatever screen the member comes back to (the app
/// resumes on whichever page they left it, which may be inside a tab or a pushed screen).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
