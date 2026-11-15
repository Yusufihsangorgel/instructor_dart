import 'dart:io';

import 'package:instructor_dart/instructor_dart.dart';

import '_ollama.dart';

final class Person {
  const Person({required this.name, required this.age, this.city});

  factory Person.fromJson(Map<String, Object?> json) => Person(
        name: json['name'] as String,
        age: json['age'] as int,
        city: json['city'] as String?,
      );

  final String name;
  final int age;
  final String? city;

  @override
  String toString() => 'Person(name: $name, age: $age, city: $city)';
}

Future<void> main() async {
  await requireOllama();
  // A server with a compatible chat completions endpoint works the same
  // way. Change baseUrl, model and apiKey to point at another one.
  final adapter = OpenAIAdapter(
    apiKey: 'ollama', // any non-empty string
    model: ollamaModel,
    baseUrl: ollamaBaseUrl,
  );

  final instructor = Instructor(adapter: adapter);
  final person = await instructor.extract(
    messages: const [Message.user('John Carmack is 55 and lives in Dallas.')],
    schema: Schema.object({
      'name': Schema.string(description: 'Full name'),
      'age': Schema.integer(min: 0, max: 130),
      'city': Schema.string().optional(),
    }),
    fromJson: Person.fromJson,
    onRetry: (attempt) => stderr.writeln(
      'retrying, attempt ${attempt.number} failed: '
      '${attempt.violations.join('; ')}',
    ),
  );

  print(person);
  adapter.close();
}
