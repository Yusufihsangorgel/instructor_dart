// Live UI from stream_struct, schema-validated result from this package.
//
//   dart run example/with_stream_struct.dart
//
// Counterpart of stream_struct's example/with_instructor.dart. That file is
// on their side of the seam: the object fills in, then one Schema.validate
// on the last frame. This file is on ours: same live fill, then
// Instructor.extract so a miss is quoted back and the model tries again.
//
// There is no function that does both. Render the partials as they arrive;
// do not validate a half-filled object (it will report "required property
// is missing" while the model is still typing). When the stream ends, the
// last frame is the first answer extract sees. A miss is a new request,
// not a replay of this stream.
//
// This package asked with a forced tool call, so the extractor is
// openAiToolDelta(), not openAiDelta. The content extractor on this stream
// would emit nothing and raise nothing.
//
// stream_struct is a dev dependency used by this file (and the test that
// locks it) only. The published package does not depend on it.
import 'package:instructor_dart/instructor_dart.dart';
import 'package:stream_struct/stream_struct.dart';

/// What the model was asked for, as the app wants to hold it.
///
/// Two factories, because the two packages disagree about when the object
/// is allowed to be incomplete. [Recipe.fromPartial] is called on every
/// growth and has to tolerate missing fields. [Recipe.fromJson] runs only
/// after [Schema.validate] passed, and can assume required fields are
/// present and correctly typed -- the same split [Instructor.extract] makes
/// internally. Reusing fromJson on a partial throws on the first fragment.
class Recipe {
  Recipe({
    required this.title,
    this.prepMinutes,
    required this.ingredients,
  });

  factory Recipe.fromPartial(Map<String, dynamic> partial) => Recipe(
        title: (partial['title'] as String?) ?? '',
        prepMinutes: partial['prep_min'] as int?,
        ingredients: (partial['ingredients'] as List?)?.cast<String>() ??
            const <String>[],
      );

  factory Recipe.fromJson(Map<String, Object?> json) => Recipe(
        title: json['title']! as String,
        prepMinutes: json['prep_min']! as int,
        ingredients: (json['ingredients']! as List).cast<String>(),
      );

  final String title;
  final int? prepMinutes;
  final List<String> ingredients;

  @override
  String toString() {
    final prep = prepMinutes == null ? '?' : '$prepMinutes min';
    final items = ingredients.isEmpty ? '(none yet)' : ingredients.join(', ');
    return '$title | $prep | $items';
  }
}

/// The schema this package sends as the tool parameters.
///
/// stream_struct never sees this. Extra keys, out-of-range numbers, and
/// missing required fields all render; extract consults the schema once,
/// on the last frame.
final recipeSchema = Schema.object({
  'title': Schema.string(description: 'Recipe title'),
  'prep_min': Schema.integer(
    description: 'Prep time in minutes',
    min: 1,
    max: 180,
  ),
  'ingredients': Schema.list(Schema.string(), minItems: 1),
});

/// One OpenAI chat-completions chunk carrying a tool-call arguments fragment.
///
/// This package always asks with a forced tool call, so the JSON arrives
/// as `choices[0].delta.tool_calls[n].function.arguments`, not as `content`.
Map<String, dynamic> _arguments(String fragment) => {
      'choices': [
        {
          'delta': {
            'tool_calls': [
              {
                'index': 0,
                'function': {'arguments': fragment},
              },
            ],
          },
        },
      ],
    };

/// A complete answer that matches [recipeSchema].
///
/// The digits of `prep_min` arrive as `2` then `20`, the same provisional
/// number the other package's examples show. Render it; do not validate it
/// yet.
final validChunks = <Map<String, dynamic>>[
  {
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'function': {
                'name': 'extract',
                'arguments': '{"title": "Foc',
              },
            },
          ],
        },
      },
    ],
  },
  _arguments('accia", "prep_min": 2'),
  _arguments('0, "ingredients": ["flour"'),
  _arguments(', "water", "olive oil"]}'),
];

/// A complete answer that fails [recipeSchema]: prep time 999 is past 180.
///
/// It looks in range at `99`, then it does not. The last frame is what
/// extract judges, not "it looked fine a moment ago".
final invalidChunks = <Map<String, dynamic>>[
  _arguments('{"title": "Burnt toast", "prep_min": 99'),
  _arguments('9, "ingredients": ["bread"]}'),
];

/// The valid object extract should land on after a repair.
const repaired = <String, Object?>{
  'title': 'Focaccia',
  'prep_min': 20,
  'ingredients': ['flour', 'water', 'olive oil'],
};

/// A model that answers from a script, so the run is the same every time.
///
/// The first reply is the last frame of the stream -- extract always
/// calls a model, and that call is how the finished object enters
/// validation. Further replies are repairs.
final class ScriptedAdapter extends LlmAdapter {
  ScriptedAdapter(this._replies, {this.log = print});

  final List<Map<String, Object?>> _replies;
  final void Function(String line) log;
  int calls = 0;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final reply = _replies[calls.clamp(0, _replies.length - 1)];
    calls++;
    log(
      '  call $calls -> tool "${request.toolName}", '
      '${request.messages.length} message(s)',
    );
    if (calls > 1) {
      final last = request.messages.last.content;
      final tail =
          last.length > 120 ? '...${last.substring(last.length - 120)}' : last;
      log('       the model is told: $tail');
    }
    log('       it answers: $reply');
    return LlmResponse.toolCall(reply);
  }
}

/// Accumulate [chunks] into the last decoded object, printing each frame.
Future<Map<String, Object?>?> fill(
  List<Map<String, dynamic>> chunks, {
  void Function(String line) log = print,
}) async {
  Map<String, dynamic>? last;
  await for (final partial in streamPartialJsonFrom(
    Stream.fromIterable(chunks),
    openAiToolDelta(),
  )) {
    if (partial is! Map<String, dynamic>) continue;
    last = partial;
    log('  ${Recipe.fromPartial(partial)}');
  }
  if (last == null) {
    log('  (no frames -- wrong extractor, or the model said nothing)');
    return null;
  }
  // Map<String, dynamic> here, Map<String, Object?> there. Same JSON;
  // the copy is the whole conversion.
  return Map<String, Object?>.from(last);
}

Future<Recipe?> play({
  required String label,
  required List<Map<String, dynamic>> chunks,
  Map<String, Object?>? repair,
  void Function(String line) log = print,
}) async {
  log(label);

  final last = await fill(chunks, log: log);
  if (last == null) {
    log('');
    return null;
  }

  final replies = <Map<String, Object?>>[last];
  if (repair != null) replies.add(repair);

  final adapter = ScriptedAdapter(replies, log: log);
  final instructor = Instructor(adapter: adapter);
  Recipe? recipe;
  try {
    recipe = await instructor.extract(
      messages: const [
        Message.user('Give me a focaccia recipe under 30 minutes.'),
      ],
      schema: recipeSchema,
      fromJson: Recipe.fromJson,
      onRetry: (attempt) => log(
        '  attempt ${attempt.number} rejected: '
        '${attempt.violations.join('; ')}',
      ),
    );
    log('  -> $recipe');
    log('     the model was called ${adapter.calls} time(s)');
  } on ExtractionException catch (e) {
    log('  -> gave up after ${e.attempts.length} attempt(s)');
  }
  instructor.close();
  log('');
  return recipe;
}

Future<void> main() async {
  print('');
  print('The object fills in as fragments arrive. extract runs once,');
  print('on the last frame. A miss is a new request, not a replay of');
  print('this stream.');
  print('');

  await play(
    label: 'fails the schema (prep_min 999 > 180)',
    chunks: invalidChunks,
    repair: repaired,
  );
  await play(
    label: 'matches the schema',
    chunks: validChunks,
  );

  print('Each line above without an arrow is a state your UI could render.');
  print('Only the arrow is a value you should keep.');
}
