# instructor_dart examples

## `mock_extract.dart` — the retry loop, no model needed

This is the package's core loop with a scripted adapter instead of a real model,
so it runs anywhere with no network: the "model" returns an out-of-range value
first, schema validation rejects it, and the retry gets a value that validates.

```
dart run example/mock_extract.dart
```

```
attempt 1 rejected: $.age: expected <= 130, got 999
extracted: Person(name: John Carmack, age: 55, city: Dallas)
the model was called 2 times
```

The shape is what you write against a real model too — a schema, a `fromJson`,
and an `onRetry` callback that sees each rejected attempt:

```dart
final person = await instructor.extract(
  messages: const [Message.user('John Carmack is 55 and lives in Dallas.')],
  schema: Schema.object({
    'name': Schema.string(description: 'Full name'),
    'age': Schema.integer(min: 0, max: 130),
    'city': Schema.string().optional(),
  }),
  fromJson: Person.fromJson,
  onRetry: (attempt) => print('attempt ${attempt.number} rejected: '
      '${attempt.violations.join('; ')}'),
);
```

## `with_stream_struct.dart` — live fill, then validate and repair

[`stream_struct`](https://pub.dev/packages/stream_struct) fills the object as
tokens arrive; this package validates a finished reply and, on a miss, retries.
`with_stream_struct.dart` is the join on this side of the seam (the other
package has `example/with_instructor.dart`). Canned forced-tool-call chunks, so
it runs offline.

```
dart run example/with_stream_struct.dart
```

The object is printed on every fragment, including a prep time that looks in
range at `99` and is not at `999`. `extract` runs once, on the last frame. A
miss is a new request, not a replay of the stream. `stream_struct` is a dev
dependency used by this file (and the test that locks it) only.

## `instructor_dart_example.dart` and `extract_demo.dart` — against a real model

Same code, pointed at a live provider. `instructor_dart_example.dart` reads
`OPENAI_API_KEY` from the environment; `extract_demo.dart` talks to a local
Ollama (`http://localhost:11434`). Any OpenAI-compatible server works — the
package README shows the Anthropic and Gemini adapters as well.

```
OPENAI_API_KEY=sk-... dart run example/instructor_dart_example.dart
```
