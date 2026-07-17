import 'dart:io';

import 'package:instructor_dart/instructor_dart.dart';

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
  // Works with any OpenAI-compatible server. For a local model:
  //   OpenAIAdapter(apiKey: 'ollama', model: 'llama3.2',
  //       baseUrl: 'http://localhost:11434/v1')
  final adapter = OpenAIAdapter(
    apiKey: Platform.environment['OPENAI_API_KEY'] ?? '',
    model: 'gpt-4o-mini',
  );

  final instructor = Instructor(adapter: adapter);
  final person = await instructor.extract(
    messages: const [
      Message.user('John Carmack is 55 and lives in Dallas.'),
    ],
    schema: Schema.object({
      'name': Schema.string(description: 'Full name'),
      'age': Schema.integer(min: 0, max: 130),
      'city': Schema.string().optional(),
    }),
    fromJson: Person.fromJson,
    onRetry: (attempt) =>
        stderr.writeln('retrying, attempt ${attempt.number} failed: '
            '${attempt.violations.join('; ')}'),
  );

  print(person);
  adapter.close();
}
