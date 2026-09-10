import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/custom_fields/domain/entities/custom_field.dart';

void main() {
  group('CustomField.fromJson', () {
    test('parses a scalar field with defaults', () {
      final f = CustomField.fromJson({
        'id': 'cf1',
        'name': 'Deal Size',
        'code': 'deal_size',
        'field_type': 'number',
        'options': <dynamic>[],
        'auto_fill': true,
        'is_filterable': true,
        'is_readonly': false,
        'is_mandatory': false,
        'sort_order': 3,
      });

      expect(f.code, 'deal_size');
      expect(f.fieldType, 'number');
      expect(f.isChoice, isFalse);
      expect(f.autoFill, isTrue);
      expect(f.sortOrder, 3);
    });

    test('parses choice options and sorts them by sort_order', () {
      final f = CustomField.fromJson({
        'id': 'cf2',
        'name': 'Segment',
        'code': 'segment',
        'field_type': 'options',
        'options': [
          {'code': 'ent', 'label': 'Enterprise', 'sort_order': 2},
          {'code': 'smb', 'label': 'SMB', 'sort_order': 1},
        ],
        'auto_fill': false,
        'is_filterable': false,
        'is_readonly': false,
        'is_mandatory': true,
        'sort_order': 0,
      });

      expect(f.isChoice, isTrue);
      expect(f.isMandatory, isTrue);
      expect(f.options.map((o) => o.code).toList(), ['smb', 'ent']);
    });

    test('an option label falls back to its code when absent', () {
      final o = CustomFieldOption.fromJson({'code': 'x'});
      expect(o.label, 'x');
    });
  });
}
