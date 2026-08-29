// What this package actually does, with no model and no network.
//
// The claim is that you get a validated typed object, and that an answer
// failing the schema is sent back for another try. Both of those happen on
// this side of the wire, so they can be shown without a provider at all.
//
// The adapter below is scripted: first reply breaks the schema, second one
// passes. Run it and watch the retry.
//
//   dart run example/no_model_demo.dart
import 'package:instructor_dart/instructor_dart.dart';

final class Person {
  const Person({required this.name, required this.age, this.city});
  factory Person.fromJson(Map<String, Object?> j) => Person(
        name: j['name']! as String,
        age: j['age']! as int,
        city: j['city'] as String?,
      );
  final String name;
  final int age;
  final String? city;
  @override
  String toString() => 'Person(name: $name, age: $age, city: $city)';
}

/// A model that answers from a script, so the run is the same every time.
///
/// Each call prints the request it was handed. That is worth seeing: the
/// schema reaches the provider as a tool declaration, and on the second call
/// the rejection is in the messages.
final class ScriptedAdapter extends LlmAdapter {
  ScriptedAdapter(this._replies);

  final List<Map<String, Object?>> _replies;
  int _calls = 0;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final reply = _replies[_calls.clamp(0, _replies.length - 1)];
    _calls++;
    print(
      '  call $_calls -> tool "${request.toolName}", '
      '${request.messages.length} message(s)',
    );
    if (_calls > 1) {
      // The retry carries why the last answer was rejected. Print the tail of
      // it: this is the part people assume a library cannot do without the
      // provider's help.
      final last = request.messages.last.content;
      final tail =
          last.length > 120 ? '...${last.substring(last.length - 120)}' : last;
      print('       the model is told: $tail');
    }
    print('       it answers: $reply');
    return LlmResponse.toolCall(reply);
  }
}

Future<void> main() async {
  final adapter = ScriptedAdapter([
    // Age is outside the declared range, so this one gets rejected here.
    {'name': 'John Carmack', 'age': 550, 'city': 'Dallas'},
    {'name': 'John Carmack', 'age': 55, 'city': 'Dallas'},
  ]);
  final instructor = Instructor(adapter: adapter);

  print('');
  print('Text in:  "John Carmack is 55 and lives in Dallas."');
  print('Schema:   age must be between 0 and 130');
  print('');

  final person = await instructor.extract(
    messages: const [Message.user('John Carmack is 55 and lives in Dallas.')],
    schema: Schema.object({
      'name': Schema.string(description: 'Full name'),
      'age': Schema.integer(min: 0, max: 130),
      'city': Schema.string().optional(),
    }),
    fromJson: Person.fromJson,
  );

  print('');
  print('Typed out: $person');
  print(
    '           age is an int, not a string that looks like one: '
    '${person.age.runtimeType}',
  );
  print('');
  print('The first answer never reached your code. It failed the schema, the');
  print('failure was quoted back, and the second answer is what you got.');
  print('');
  print('Point the same call at a real model with:');
  print('  dart run example/extract_demo.dart');

  instructor.close();
}
