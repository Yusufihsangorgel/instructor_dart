import 'package:instructor_dart/instructor_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Schema.object does not alias the caller map', () {
    test('mutating the passed map does not reach the schema', () {
      final props = <String, Schema>{'name': Schema.string()};
      final schema = Schema.object(props);

      props['injected'] = Schema.integer();

      final properties =
          schema.toJsonSchema()['properties'] as Map<String, Object?>;
      expect(properties.keys, ['name']);
      expect(schema.validate(<String, Object?>{'name': 'x'}), isEmpty);
    });

    test('the exposed properties map is unmodifiable', () {
      final schema = Schema.object({'name': Schema.string()});
      expect(
        () => schema.properties['injected'] = Schema.integer(),
        throwsUnsupportedError,
      );
    });

    test('optional() still works after the copy', () {
      final schema = Schema.object({'name': Schema.string()});
      expect(schema.optional().isOptional, isTrue);
    });
  });

  group('SchemaViolation value equality', () {
    test('equal violations compare equal and deduplicate in a set', () {
      final a = SchemaViolation(r'$.age', 'must be an ${'integer'}');
      final b = SchemaViolation(r'$.age', 'must be an ${'integer'}');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(<SchemaViolation>{a, b}, hasLength(1));
    });

    test('a difference in either field breaks equality', () {
      const base = SchemaViolation(r'$.age', 'must be an integer');
      expect(
          base, isNot(const SchemaViolation(r'$.name', 'must be an integer')));
      expect(base, isNot(const SchemaViolation(r'$.age', 'must be a string')));
    });
  });

  group('Message value equality', () {
    test('runtime-built messages compare equal, not only const ones', () {
      final a = Message(MessageRole.user, 'hi'.toUpperCase());
      final b = Message(MessageRole.user, 'HI');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('role and content both matter', () {
      const base = Message.user('hi');
      expect(base, isNot(const Message.system('hi')));
      expect(base, isNot(const Message.user('bye')));
    });
  });
}
