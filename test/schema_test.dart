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
        Schema.string(
          minLength: 2,
          maxLength: 5,
          pattern: r'^[a-z]+$',
        ).toJsonSchema(),
        {
          'type': 'string',
          'minLength': 2,
          'maxLength': 5,
          'pattern': r'^[a-z]+$',
        },
      );
      expect(Schema.number(min: 0.5).toJsonSchema(), {
        'type': 'number',
        'minimum': 0.5,
      });
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
      expect(
        violations.map((v) => v.message),
        everyElement(contains('missing')),
      );
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

    test('treats an explicit null on an optional property as absent', () {
      expect(
        schema.validate({
          'name': 'Ada',
          'age': 36,
          'role': 'admin',
          'tags': ['math'],
          'address': null,
        }),
        isEmpty,
      );
    });

    test('still rejects an explicit null on a required property', () {
      final violations = schema.validate({
        'name': null,
        'age': 36,
        'role': 'admin',
        'tags': ['math'],
      });
      expect(violations.single.path, r'$.name');
      expect(violations.single.message, contains('got null'));
    });

    test('treats null on every optional leaf schema kind as absent', () {
      // Forced tool calling on OpenAI, Anthropic and Gemini fills in every
      // declared parameter and represents "no value" as an explicit `null`
      // rather than omitting the key, so this must hold for every schema
      // type, not just the one that happens to be exercised elsewhere.
      final s = Schema.object({
        'name': Schema.string(),
        'city': Schema.string().optional(),
        'nickname': Schema.enumeration(['a', 'b']).optional(),
        'score': Schema.number().optional(),
        'count': Schema.integer().optional(),
        'active': Schema.boolean().optional(),
        'tags': Schema.list(Schema.string()).optional(),
        'address': Schema.object({'street': Schema.string()}).optional(),
      });
      expect(
        s.validate({
          'name': 'Ada',
          'city': null,
          'nickname': null,
          'score': null,
          'count': null,
          'active': null,
          'tags': null,
          'address': null,
        }),
        isEmpty,
      );
    });

    test('tolerates unexpected properties when allowed', () {
      final open = Schema.object({
        'name': Schema.string(),
      }, allowAdditionalProperties: true);
      expect(open.validate({'name': 'Ada', 'extra': 1}), isEmpty);
    });

    test('rejects non-object roots', () {
      expect(
        schema.validate('nope').single.message,
        contains('expected an object'),
      );
      expect(schema.validate(null).single.message, contains('got null'));
    });

    test('validates string pattern', () {
      final s = Schema.string(pattern: r'^\d{4}$');
      expect(s.validate('1234'), isEmpty);
      expect(s.validate('12a4').single.message, contains('pattern'));
    });

    test('accepts integral doubles as integers (JSON Schema semantics)', () {
      final s = Schema.integer(min: 0, max: 130);
      expect(s.validate(25.0), isEmpty);
      expect(s.validate(25.5).single.message, contains('expected an integer'));
      expect(
        s.validate(double.nan).single.message,
        contains('expected an integer'),
      );
      expect(s.validate(200.0).single.message, contains('expected <= 130'));
    });

    test('rejects invalid patterns and empty enums at construction', () {
      expect(() => Schema.string(pattern: '('), throwsFormatException);
      expect(() => Schema.enumeration([]), throwsArgumentError);
    });

    test('enumeration copies its values', () {
      final values = ['a', 'b'];
      final s = Schema.enumeration(values);
      values.add('c');
      expect((s.toJsonSchema()['enum'] as List), ['a', 'b']);
    });

    test('concrete schema types are built only through the factories', () {
      // The concrete constructors are library-private, so the validating
      // factories are the only construction path from outside the library; a
      // direct `StringSchema(pattern: '(')` or `EnumSchema([])` can no longer
      // skip the checks below. The concrete types stay public for return-type,
      // `switch`, and field access.
      expect(Schema.string(pattern: r'^\d+$'), isA<StringSchema>());
      expect(Schema.enumeration(['a', 'b']), isA<EnumSchema>());
      expect(() => Schema.string(pattern: '('), throwsFormatException);
      expect(() => Schema.enumeration(<String>[]), throwsArgumentError);
    });
  });

  group('JSON Schema keyword coverage', () {
    test('toJsonSchema emits exactly the keywords this package claims', () {
      // Every factory argument that can appear on the wire, in one tree.
      // If a keyword starts being forwarded without a matching validate
      // check, it shows up here and has to be classified.
      final schema = Schema.object({
        'name': Schema.string(
          description: 'n',
          minLength: 1,
          maxLength: 10,
          pattern: r'^[a-z]+$',
        ),
        'age': Schema.integer(description: 'a', min: 0, max: 130),
        'score': Schema.number(description: 's', min: 0.5, max: 9.5),
        'ok': Schema.boolean(description: 'b'),
        'role': Schema.enumeration(['admin', 'user'], description: 'r'),
        'tags': Schema.list(
          Schema.string(),
          description: 't',
          minItems: 1,
          maxItems: 5,
        ),
        'address': Schema.object({
          'street': Schema.string(),
          'zip': Schema.string().optional(),
        }, description: 'addr', allowAdditionalProperties: true),
        'note': Schema.string().optional(),
      }, description: 'person');

      expect(_jsonSchemaKeywords(schema.toJsonSchema()), {
        'additionalProperties',
        'description',
        'enum',
        'items',
        'maxItems',
        'maxLength',
        'maximum',
        'minItems',
        'minLength',
        'minimum',
        'pattern',
        'properties',
        'required',
        'type',
      });
    });

    test('every expressed constraint keyword actually rejects', () {
      expect(Schema.string().validate(1), isNotEmpty);
      expect(Schema.string(minLength: 2).validate('a'), isNotEmpty);
      expect(Schema.string(maxLength: 1).validate('ab'), isNotEmpty);
      expect(Schema.string(pattern: r'^a$').validate('b'), isNotEmpty);
      expect(Schema.integer().validate('1'), isNotEmpty);
      expect(Schema.integer(min: 0).validate(-1), isNotEmpty);
      expect(Schema.integer(max: 1).validate(2), isNotEmpty);
      expect(Schema.number().validate('1'), isNotEmpty);
      expect(Schema.number(min: 0.5).validate(0.4), isNotEmpty);
      expect(Schema.number(max: 1.5).validate(1.6), isNotEmpty);
      expect(Schema.boolean().validate(1), isNotEmpty);
      expect(Schema.enumeration(['a']).validate('b'), isNotEmpty);
      expect(Schema.list(Schema.string()).validate('x'), isNotEmpty);
      expect(
        Schema.list(Schema.string(), minItems: 1).validate(<String>[]),
        isNotEmpty,
      );
      expect(
        Schema.list(Schema.string(), maxItems: 1).validate(['a', 'b']),
        isNotEmpty,
      );
      expect(Schema.list(Schema.integer()).validate(['x']), isNotEmpty);
      expect(Schema.object({'x': Schema.string()}).validate({}), isNotEmpty);
      expect(
        Schema.object({'x': Schema.string()}).validate({'x': 'a', 'y': 1}),
        isNotEmpty,
      );
    });

    test('description is forwarded and is not a constraint', () {
      // The only emitted keyword validate does not check. A description
      // that reads like a format or a pattern is still only text for the
      // model; putting the constraint there does not enforce it.
      final s = Schema.string(description: 'RFC 5322 email address');
      expect(s.toJsonSchema()['description'], 'RFC 5322 email address');
      expect(s.validate('not-an-email'), isEmpty);
    });

    test('pattern is unanchored, matching JSON Schema', () {
      // JSON Schema pattern uses an unanchored search; Dart's hasMatch
      // does the same. Callers who want a full-string match write ^ and $.
      final s = Schema.string(pattern: r'\d{4}');
      expect(s.validate('1234'), isEmpty);
      expect(s.validate('x1234y'), isEmpty);
      expect(s.validate('12a4'), isNotEmpty);
    });

    test(
        'minimum and maximum are inclusive; exclusive bounds cannot be written',
        () {
      final n = Schema.number(min: 0, max: 10);
      expect(n.toJsonSchema().containsKey('exclusiveMinimum'), isFalse);
      expect(n.toJsonSchema().containsKey('exclusiveMaximum'), isFalse);
      expect(n.validate(0), isEmpty);
      expect(n.validate(10), isEmpty);
      expect(n.validate(-0.1), isNotEmpty);
      expect(n.validate(10.1), isNotEmpty);

      final i = Schema.integer(min: 0, max: 2);
      expect(i.validate(0), isEmpty);
      expect(i.validate(2), isEmpty);
    });

    test('uniqueItems is not expressed; duplicate list items pass', () {
      final s = Schema.list(Schema.string());
      expect(s.toJsonSchema().containsKey('uniqueItems'), isFalse);
      expect(s.validate(['a', 'a']), isEmpty);
    });

    test('format is not expressed, and a description is not a format check',
        () {
      final s = Schema.string(description: 'email');
      expect(s.toJsonSchema().containsKey('format'), isFalse);
      expect(s.validate('not-an-email'), isEmpty);
    });

    test('minLength and maxLength count Dart String.length, not code points',
        () {
      // JSON Schema counts Unicode characters; Dart counts UTF-16 units.
      // U+1F44D is one code point and two units, so maxLength: 1 rejects it.
      const thumbsUp = '\u{1F44D}';
      expect(thumbsUp.length, 2);
      final one = Schema.string(minLength: 1, maxLength: 1);
      expect(one.validate('a'), isEmpty);
      expect(one.validate(thumbsUp), isNotEmpty);
      expect(Schema.string(minLength: 2).validate(thumbsUp), isEmpty);
    });

    test(
        'additionalProperties as a schema cannot be written; true allows any extra',
        () {
      final open = Schema.object({
        'name': Schema.string(),
      }, allowAdditionalProperties: true);
      expect(open.toJsonSchema()['additionalProperties'], isTrue);
      expect(
        open.validate({'name': 'Ada', 'extra': 1, 'also': <Object?>[]}),
        isEmpty,
      );
    });
  });

  group('valid JSON that is still the wrong object', () {
    // The README table of cases native JSON mode can still return. If a
    // message or a normalize result here changes, the table is lying.

    test('rejects an out-of-range integer that is still a JSON integer', () {
      final s = Schema.integer(min: 0, max: 130);
      expect(s.validate(999).single.message, 'expected <= 130, got 999');
      expect(s.validate(999.0).single.message, 'expected <= 130, got 999.0');
    });

    test('rejects an enum value outside the set, including a case fold', () {
      final s = Schema.enumeration(['admin', 'user']);
      expect(
        s.validate('root').single.message,
        'expected one of admin, user, got root',
      );
      expect(
        s.validate('Admin').single.message,
        'expected one of admin, user, got Admin',
      );

      // Anthropic documents that structured outputs may change enum
      // capitalization and still complete normally. Exact match here is
      // what makes that a violation this package will quote back.
      final topics = Schema.enumeration([
        'Conversation Topic 1',
        'Conversation Topic 2',
        'Conversation topic 3',
      ]);
      expect(
        topics.validate('Conversation Topic 3').single.message,
        'expected one of Conversation Topic 1, Conversation Topic 2, '
        'Conversation topic 3, got Conversation Topic 3',
      );
      expect(topics.validate('Conversation topic 3'), isEmpty);
    });

    test('collapses a VM-decoded 25.0 to int, leaves values past 2^53', () {
      final s = Schema.integer();
      expect(s.validate(25.0), isEmpty);
      expect(s.normalize(25.0), same(25));
      expect(s.normalize(25.0), isA<int>());
      expect(s.normalize(25), same(25));

      const pastSafe = 9007199254740994.0; // 2^53 + 2
      expect(s.validate(pastSafe), isEmpty);
      expect(s.normalize(pastSafe), isA<double>());
    });
  });
}

/// JSON Schema keyword names in a [Schema.toJsonSchema] tree.
///
/// Property names under `properties` are not keywords; only the nested
/// schemas' own keys are. `enum` / `required` values are strings, not schemas.
Set<String> _jsonSchemaKeywords(Object? node) {
  if (node is! Map) return {};
  final keys = <String>{};
  for (final entry in node.entries) {
    final key = entry.key as String;
    keys.add(key);
    if (key == 'properties' && entry.value is Map) {
      for (final property in (entry.value as Map).values) {
        keys.addAll(_jsonSchemaKeywords(property));
      }
    } else if (key == 'items' ||
        (key == 'additionalProperties' && entry.value is Map)) {
      keys.addAll(_jsonSchemaKeywords(entry.value));
    }
  }
  return keys;
}
