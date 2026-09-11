import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/external_url_launcher.dart';

/// Same seam as `documentExternalUrlLauncherProvider`/WhatsApp's own —
/// a fake stands in for `flutter test`, which has no platform channel
/// to actually place a call.
final dialerUrlLauncherProvider = Provider<ExternalUrlLauncher>((ref) => DefaultExternalUrlLauncher());
