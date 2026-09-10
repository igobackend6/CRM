import 'entities/template_variables.dart';

final _tokenPattern = RegExp(r'\{\{\s*([a-zA-Z_]+)\s*\}\}');

/// Renders a template body (§7), replacing every `{{known_variable}}`
/// token with its value. A token whose name isn't one of
/// [TemplateVariables]'s five known keys is left exactly as written
/// (§7 "preserve unknown variables ... consistently") rather than
/// removed or guessed at — malformed/unrecognized syntax should be
/// obvious in the preview, not silently swallowed.
String renderMessageTemplate(String body, TemplateVariables variables) {
  final values = variables.toMap();
  return body.replaceAllMapped(_tokenPattern, (match) {
    final key = match.group(1)!;
    return values.containsKey(key) ? values[key]! : match.group(0)!;
  });
}
