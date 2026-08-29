// Demo for the write-up: unstructured text in, a validated typed object out,
// using a local model. Run with: dart run example/extract_demo.dart
import 'package:instructor_dart/instructor_dart.dart';

import '_ollama.dart';

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

Future<void> main() async {
  await requireOllama();
  final instructor = Instructor(
    adapter: OpenAIAdapter(
      apiKey: 'ollama',
      model: ollamaModel,
      baseUrl: ollamaBaseUrl,
    ),
  );

  const text = 'John Carmack is 55 and lives in Dallas.';
  print('');
  print('Text in:  "$text"');
  print('');
  print('Asking $ollamaModel locally...');
  print('');

  final person = await instructor.extract(
    messages: const [Message.user(text)],
    schema: Schema.object({
      'name': Schema.string(description: 'Full name'),
      'age': Schema.integer(min: 0, max: 130),
      'city': Schema.string().optional(),
    }),
    fromJson: Person.fromJson,
  );

  print('Dart out: $person');
  print('          (a real ${person.runtimeType}, not a Map)');
}
