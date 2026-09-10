import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/whatsapp/domain/entities/template_variables.dart';
import 'package:mobile/features/whatsapp/domain/message_template_renderer.dart';

void main() {
  group('renderMessageTemplate', () {
    test('replaces every known variable', () {
      const variables = TemplateVariables(name: 'Jane', phone: '+15551234567', status: 'Qualified', assignedMember: 'Rep One');
      final result = renderMessageTemplate(
        'Hello {{name}}, your status is {{status}} and your rep is {{assigned_member}} ({{phone}}).',
        variables,
      );
      expect(result, 'Hello Jane, your status is Qualified and your rep is Rep One (+15551234567).');
    });

    test('a missing value renders as an empty string, not the literal token or "null"', () {
      const variables = TemplateVariables(name: 'Jane');
      final result = renderMessageTemplate('Hi {{name}}, from {{company}}.', variables);
      expect(result, 'Hi Jane, from .');
    });

    test('an unrecognized variable name is preserved verbatim', () {
      const variables = TemplateVariables(name: 'Jane');
      final result = renderMessageTemplate('Hi {{name}}, ref {{ticket_id}}.', variables);
      expect(result, 'Hi Jane, ref {{ticket_id}}.');
    });

    test('a template with no variables at all is returned unchanged', () {
      const variables = TemplateVariables(name: 'Jane');
      expect(renderMessageTemplate('Just a plain message.', variables), 'Just a plain message.');
    });

    test('malformed/incomplete braces are never matched or partially replaced', () {
      const variables = TemplateVariables(name: 'Jane');
      final result = renderMessageTemplate('Hi {name}} and {{name, and {{ name }}.', variables);
      expect(result, 'Hi {name}} and {{name, and Jane.');
    });
  });
}
