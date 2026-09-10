import 'package:url_launcher/url_launcher.dart' as launcher;

/// Thin abstraction over `url_launcher` (opening a signed document URL,
/// or a `wa.me` WhatsApp deep link) — the same "swap out a real plugin
/// for a fake in tests" seam as CsvFilePicker/DocumentFilePicker, since
/// `flutter test` has no platform channel to actually open a URL.
abstract class ExternalUrlLauncher {
  Future<bool> launch(Uri uri);
}

class DefaultExternalUrlLauncher implements ExternalUrlLauncher {
  @override
  Future<bool> launch(Uri uri) async {
    if (!await launcher.canLaunchUrl(uri)) return false;
    return launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
  }
}
