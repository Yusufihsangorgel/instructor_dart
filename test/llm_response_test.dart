import 'package:instructor_dart/instructor_dart.dart';
import 'package:test/test.dart';

void main() {
  group('LlmResponse constructors', () {
    test('LlmResponse.toolCall exposes arguments and leaves text null', () {
      const response = LlmResponse.toolCall({'name': 'John', 'age': 25});

      expect(response.toolArguments, {'name': 'John', 'age': 25});
      expect(response.text, isNull);
    });

    test('LlmResponse.text exposes text and leaves toolArguments null', () {
      const response = LlmResponse.text('not json at all');

      expect(response.text, 'not json at all');
      expect(response.toolArguments, isNull);
    });

    test('LlmResponse.empty leaves both fields null', () {
      const response = LlmResponse.empty();

      expect(response.toolArguments, isNull);
      expect(response.text, isNull);
    });

    test('LlmResponse.text accepts an empty string', () {
      // The three bundled adapters normalize an empty join to `null`, but the
      // constructor still has to be able to represent a provider that really
      // answered with nothing rather than not answering.
      const response = LlmResponse.text('');

      expect(response.text, isEmpty);
      expect(response.toolArguments, isNull);
    });

    test('the deprecated unnamed constructor still carries what it was given',
        () {
      // Deprecating it must not change what it does. An adapter that has not
      // migrated yet keeps working; it only gets a warning telling it which
      // constructor to move to.
      const response = LlmResponse(
        toolArguments: {'name': 'John'},
        text: 'commentary the caller does not need',
      );

      expect(response.toolArguments, {'name': 'John'});
      expect(response.text, 'commentary the caller does not need');
    });
  });
}
