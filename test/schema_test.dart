import 'package:instructor_dart/instructor_dart.dart';
import 'package:test/test.dart';

void main() {
  group('toJsonSchema', () {
    test('renders a nested object schema', () {
      final schema = Schema.object({
        'name': Schema.string(description: 'Full name'),
        'age': Schema.integer(min: 0, max: 130),
        'tags': Schema.list(Schema.string(), minItems: 1),
        'city': Schema.string().optional(),
        'role': Schema.enumeration(['admin', 'user']),
        'address': Schema.object({'street': Schema.string()}),
      });

      expect(schema.toJsonSchema(), {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Full name'},
          'age': {'type': 'integer', 'minimum': 0, 'maximum': 130},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 1,
          },
          'city': {'type': 'string'},
          'role': {
            'type': 'string',
            'enum': ['admin', 'user'],
          },
          'address': {
            'type': 'object',
            'properties': {
              'street': {'type': 'string'},
            },
            'required': ['street'],
            'additionalProperties': false,
          },
        },
        'required': ['name', 'age', 'tags', 'role', 'address'],
        'additionalProperties': false,
      });
    });

    test('renders string constraints and number bounds', () {
      expect(
        Schema.string(minLength: 2, maxLength: 5, pattern: r'^[a-z]+$')
            .toJsonSchema(),
        {
          'type': 'string',
          'minLength': 2,
          'maxLength': 5,
          'pattern': r'^[a-z]+$',
        },
      );
      expect(Schema.number(min: 0.5).toJsonSchema(),
          {'type': 'number', 'minimum': 0.5});
      expect(Schema.boolean().toJsonSchema(), {'type': 'boolean'});
    });

    test('omits an empty required list', () {
      final schema = Schema.object({'note': Schema.string().optional()});
      expect(schema.toJsonSchema().containsKey('required'), isFalse);
    });
  });

  group('validate', () {
    final schema = Schema.object({
      'name': Schema.string(minLength: 1),
      'age': Schema.integer(min: 0),
      'role': Schema.enumeration(['admin', 'user']),
      'tags': Schema.list(Schema.string()),
      'address': Schema.object({'street': Schema.string()}).optional(),
    });

    test('accepts conforming data', () {
      expect(
        schema.validate({
          'name': 'Ada',
          'age': 36,
          'role': 'admin',
          'tags': ['math'],
        }),
        isEmpty,
      );
    });

    test('reports missing required properties', () {
      final violations = schema.validate({'name': 'Ada'});
      expect(
        violations.map((v) => v.path),
        containsAll([r'$.age', r'$.role', r'$.tags']),
      );
      expect(violations.map((v) => v.message),
          everyElement(contains('missing')));
    });

    test('reports type mismatches with paths', () {
      final violations = schema.validate({
        'name': 'Ada',
        'age': 'old',
        'role': 'admin',
        'tags': ['ok', 7],
      });
      expect(
        violations.map((v) => v.toString()),
        containsAll([
          contains(r'$.age: expected an integer'),
          contains(r'$.tags[1]: expected a string'),
        ]),
      );
    });

    test('reports nested object violations', () {
      final violations = schema.validate({
        'name': 'Ada',
        'age': 1,
        'role': 'admin',
        'tags': <String>[],
        'address': {'street': 5},
      });
      expect(violations, hasLength(1));
      expect(violations.single.path, r'$.address.street');
    });

    test('reports out-of-range and enum violations', () {
      final violations = schema.validate({
        'name': '',
        'age': -1,
        'role': 'root',
        'tags': <String>[],
      });
      expect(
        violations.map((v) => v.path),
        containsAll([r'$.name', r'$.age', r'$.role']),
      );
    });

    test('rejects unexpected properties by default', () {
      final violations = schema.validate({
        'name': 'Ada',
        'age': 1,
        'role': 'user',
        'tags': <String>[],
        'extra': true,
      });
      expect(violations, hasLength(1));
      expect(violations.single.path, r'$.extra');
      expect(violations.single.message, 'unexpected property');
    });

    test('tolerates unexpected properties when allowed', () {
      final open = Schema.object(
        {'name': Schema.string()},
        allowAdditionalProperties: true,
      );
      expect(open.validate({'name': 'Ada', 'extra': 1}), isEmpty);
    });

    test('rejects non-object roots', () {
      expect(schema.validate('nope').single.message,
          contains('expected an object'));
      expect(schema.validate(null).single.message, contains('got null'));
    });

    test('validates string pattern', () {
      final s = Schema.string(pattern: r'^\d{4}$');
      expect(s.validate('1234'), isEmpty);
      expect(s.validate('12a4').single.message, contains('pattern'));
    });
  });
}
