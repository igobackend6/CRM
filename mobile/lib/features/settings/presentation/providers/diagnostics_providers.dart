import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/auth_state.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../leads/presentation/providers/leads_providers.dart' show leadLocationServiceProvider;
import '../../../workspace/domain/entities/workspace_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/server_ping.dart';
import '../../domain/diagnostic_check.dart';
import 'settings_providers.dart';

final serverPingProvider = Provider<ServerPing>((ref) => ApiServerPing());

/// Runs the Troubleshooting checks. Each one is independent, so a failure in one never hides the rest.
final diagnosticsProvider = FutureProvider.autoDispose<List<DiagnosticCheck>>((ref) async {
  final checks = <DiagnosticCheck>[];

  final ms = await ref.read(serverPingProvider).pingMilliseconds();
  checks.add(
    ms == null
        ? const DiagnosticCheck(
            label: 'Server connection',
            status: DiagnosticStatus.problem,
            detail: 'Could not reach the server. Check your internet connection and try again.',
          )
        : DiagnosticCheck(label: 'Server connection', status: DiagnosticStatus.ok, detail: 'Reachable ($ms ms)'),
  );

  final auth = ref.read(authControllerProvider);
  checks.add(
    auth.status == AuthStatus.authenticated
        ? const DiagnosticCheck(label: 'Sign-in', status: DiagnosticStatus.ok, detail: 'Signed in')
        : const DiagnosticCheck(label: 'Sign-in', status: DiagnosticStatus.problem, detail: 'Not signed in. Sign in again.'),
  );

  final workspace = ref.read(workspaceControllerProvider);
  final selected = workspace.selected;
  checks.add(
    workspace.status == WorkspaceStatus.selected && selected != null
        ? DiagnosticCheck(label: 'Workspace', status: DiagnosticStatus.ok, detail: selected.workspace.name)
        : const DiagnosticCheck(label: 'Workspace', status: DiagnosticStatus.warning, detail: 'No workspace is selected.'),
  );

  bool locationAllowed;
  try {
    // Bounded: a platform call that never answers must not leave the screen spinning forever.
    locationAllowed = await ref.read(leadLocationServiceProvider).hasPermission().timeout(const Duration(seconds: 5));
  } catch (_) {
    locationAllowed = false;
  }
  checks.add(
    locationAllowed
        ? const DiagnosticCheck(label: 'Location permission', status: DiagnosticStatus.ok, detail: 'Allowed')
        : const DiagnosticCheck(
            label: 'Location permission',
            status: DiagnosticStatus.info,
            detail: 'Not allowed. Only needed to save a lead\'s location; you can allow it in your phone\'s app settings.',
          ),
  );

  final loggingOn = ref.read(appSettingsControllerProvider).loggingEnabled;
  final lines = AppLogger.bufferedLines.length;
  checks.add(
    DiagnosticCheck(
      label: 'Diagnostic log',
      status: DiagnosticStatus.info,
      detail: loggingOn ? 'On. $lines ${lines == 1 ? 'line' : 'lines'} captured.' : 'Off. Turn on "Enable Log" in Settings to capture one.',
    ),
  );

  return checks;
});
