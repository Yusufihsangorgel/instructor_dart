import 'package:instructor_dart/instructor_dart.dart';
import 'package:test/test.dart';

final class _ScriptedAdapter implements LlmAdapter {
  _ScriptedAdapter(this.responses);

  final List<LlmResponse> responses;
  final List<LlmRequest> requests = [];
  var _next = 0;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    requests.add(request);
    return responses[_next++];
  }
}

final class _Person {
  const _Person(this.name, this.age);

  factory _Person.fromJson(Map<String, Object?> json) =>
      _Person(json['name'] as String, json['age'] as int);

  final String name;
  final int age;
}

void main() {
  final schema = Schema.object({
    'name': Schema.string(),
    'age': Schema.integer(min: 0),
  });
  final messages = [const Message.user('John is 25.')];

  test('returns typed data from a valid tool call', () async {
    final adapter = _ScriptedAdapter([
      const LlmResponse(toolArguments: {'name': 'John', 'age': 25}),
    ]);
    final person = await Instructor(adapter: adapter).extract(
      messages: messages,
      schema: schema,
      fromJson: _Person.fromJson,
    );
    expect(person.name, 'John');
    expect(person.age, 25);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.jsonSchema['type'], 'object');
  });

  test('parses JSON out of plain text and fenced blocks', () async {
    final adapter = _ScriptedAdapter([
      const LlmResponse(
          text: 'Sure:\n```json\n{"name": "John", "age": 25}\n```'),
    ]);
    final raw = await Instructor(adapter: adapter)
        .extractRaw(messages: messages, schema: schema);
    expect(raw, {'name': 'John', 'age': 25});
  });

  test('feeds violations back and succeeds on retry', () async {
    final adapter = _ScriptedAdapter([
      const LlmResponse(toolArguments: {'name': 'John', 'age': -3}),
      const LlmResponse(toolArguments: {'name': 'John', 'age': 25}),
    ]);
    final retries = <ExtractionAttempt>[];
    final raw = await Instructor(adapter: adapter).extractRaw(
      messages: messages,
      schema: schema,
      onRetry: retries.add,
    );

    expect(raw['age'], 25);
    expect(retries, hasLength(1));
    expect(retries.single.violations.single.path, r'$.age');

    // The second request carries the repair conversation.
    final repair = adapter.requests[1].messages;
    expect(repair, hasLength(3));
    expect(repair[1].role, MessageRole.assistant);
    expect(repair[2].role, MessageRole.user);
    expect(repair[2].content, contains(r'$.age'));
    expect(repair[2].content, contains('extract'));
  });

  test('throws with full attempt history when retries are exhausted', () async {
    final adapter = _ScriptedAdapter([
      const LlmResponse(text: 'not json at all'),
      const LlmResponse(toolArguments: {'name': 7, 'age': 25}),
    ]);
    await expectLater(
      Instructor(adapter: adapter).extractRaw(
        messages: messages,
        schema: schema,
        maxRetries: 1,
      ),
      throwsA(isA<ExtractionException>()
          .having((e) => e.attempts, 'attempts', hasLength(2))
          .having((e) => e.attempts.first.violations.single.message,
              'first attempt', contains('not a JSON object'))
          .having((e) => e.attempts.last.violations.single.path,
              'last attempt path', r'$.name')),
    );
  });

  test('maxRetries: 0 gives exactly one attempt', () async {
    final adapter = _ScriptedAdapter([
      const LlmResponse(text: 'nope'),
    ]);
    await expectLater(
      Instructor(adapter: adapter)
          .extractRaw(messages: messages, schema: schema, maxRetries: 0),
      throwsA(isA<ExtractionException>()),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('rejects negative maxRetries', () {
    final adapter = _ScriptedAdapter([]);
    expect(
      () => Instructor(adapter: adapter)
          .extractRaw(messages: messages, schema: schema, maxRetries: -1),
      throwsArgumentError,
    );
  });

  test('coerces integral doubles to int, including nested ones', () async {
    // On the VM, jsonDecode('25.0') yields a double; models regularly emit
    // integers this way. The result must still satisfy `as int` casts.
    final adapter = _ScriptedAdapter([
      const LlmResponse(toolArguments: {
        'name': 'John',
        'age': 25.0,
        'scores': [1.0, 2.5],
      }),
    ]);
    final nested = Schema.object({
      'name': Schema.string(),
      'age': Schema.integer(min: 0),
      'scores': Schema.list(Schema.number()),
    });
    final raw = await Instructor(adapter: adapter)
        .extractRaw(messages: messages, schema: nested);
    expect(raw['age'], same(25));
    expect(raw['age'], isA<int>());
    expect(raw['scores'], [1, 2.5]);
  });

  test('whole-valued number field decodes to double, integer stays int',
      () async {
    // A model often writes a whole number like 42 for a `number` field. It
    // must arrive as a double so `json['price'] as double` in fromJson does
    // not throw, while an `integer` field given the same value stays an int.
    final adapter = _ScriptedAdapter([
      const LlmResponse(toolArguments: {'price': 42, 'age': 42}),
    ]);
    final schema = Schema.object({
      'price': Schema.number(),
      'age': Schema.integer(),
    });
    final raw = await Instructor(adapter: adapter)
        .extractRaw(messages: messages, schema: schema);
    expect(raw['price'], isA<double>());
    expect(raw['price'], 42.0);
    expect(() => raw['price'] as double, returnsNormally);
    expect(raw['age'], isA<int>());
    expect(raw['age'], same(42));
    expect(() => raw['age'] as int, returnsNormally);
  });

  test('fractional doubles still fail integer validation', () async {
    final adapter = _ScriptedAdapter([
      const LlmResponse(toolArguments: {'name': 'John', 'age': 25.5}),
    ]);
    await expectLater(
      Instructor(adapter: adapter)
          .extractRaw(messages: messages, schema: schema, maxRetries: 0),
      throwsA(isA<ExtractionException>()),
    );
  });
}
