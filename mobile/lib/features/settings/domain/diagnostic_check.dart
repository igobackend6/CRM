enum DiagnosticStatus { ok, warning, problem, info }

/// One line on the Troubleshooting screen: what was checked and what was found.
class DiagnosticCheck {
  const DiagnosticCheck({required this.label, required this.status, required this.detail});

  final String label;
  final DiagnosticStatus status;
  final String detail;
}
