// The package's core loop, with no model or network: a scripted adapter returns
// an invalid object first and a valid one second, so you can watch the schema
// validation reject the first attempt and the retry succeed.
//
//   dart run example/mock_extract.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instructor_dart/instructor_dart.dart';

final class Person {
  const Person({required this.name, required this.age, this.city});
  factory Person.fromJson(Map<String, Object?> j) => Person(
        name: j['name'] as String,
        age: j['age'] as int,
        city: j['city'] as String?,
      );
  final String name;
  final int age;
  final String? city;
  @override
  String toString() => 'Person(name: $name, age: $age, city: $city)';
}

/// One OpenAI-shaped response carrying a forced tool call with [arguments].
http.Response _toolCall(String arguments) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {
              'tool_calls': [
                {
                  'function': {'name': 'extract', 'arguments': arguments},
                },
              ],
            },
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

Future<void> main() async {
  // The scripted model: age 999 first (out of the schema's 0..130 range), then
  // a value that validates. A real model produces the same shapes; here they
  // are fixed so the demo is deterministic.
  final scripted = <String>[
    '{"name": "John Carmack", "age": 999, "city": "Dallas"}',
    '{"name": "John Carmack", "age": 55, "city": "Dallas"}',
  ];
  var call = 0;
  final client = MockClient((_) async => _toolCall(scripted[call++]));

  final instructor = Instructor(
    adapter: OpenAIAdapter(apiKey: 'unused', model: 'mock', client: client),
  );

  final person = await instructor.extract(
    messages: const [Message.user('John Carmack is 55 and lives in Dallas.')],
    schema: Schema.object({
      'name': Schema.string(description: 'Full name'),
      'age': Schema.integer(min: 0, max: 130),
      'city': Schema.string().optional(),
    }),
    fromJson: Person.fromJson,
    onRetry: (attempt) => print(
      'attempt ${attempt.number} rejected: '
      '${attempt.violations.join('; ')}',
    ),
  );

  print('extracted: $person');
  print('the model was called $call times');
  instructor.close();
}
