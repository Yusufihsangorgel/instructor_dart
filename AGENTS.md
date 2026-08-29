# AGENTS.md

For agents changing this package, or calling it to pull a typed object out of a model.

## What it is

`instructor_dart` sends your `Schema` to a model as a forced tool call, validates the reply against that same schema, and returns a Dart object through your `fromJson`. It does not ship an HTTP client or manage keys — you pass `apiKey` into `OpenAIAdapter`, `AnthropicAdapter`, or `GeminiAdapter` (optionally your own `http.Client`), or you extend `LlmAdapter`; if the provider's own structured-output mode already returns JSON you accept, you do not need this package.

## Usage

Same `extract` call as `example/instructor_dart_example.dart`. You supply the adapter and key, the `Person` type, and `fromJson`. `fromJson` runs only after validation.

```dart
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
}

Future<Person> extractPerson({required String apiKey}) async {
  final instructor = Instructor(
    adapter: OpenAIAdapter(apiKey: apiKey, model: 'gpt-4o-mini'),
  );
  final person = await instructor.extract(
    messages: const [Message.user('John Carmack is 55 and lives in Dallas.')],
    schema: Schema.object({
      'name': Schema.string(description: 'Full name'),
      'age': Schema.integer(min: 0, max: 130),
      'city': Schema.string().optional(),
    }),
    fromJson: Person.fromJson,
  );
  instructor.close();
  return person;
}
```

`extract` / `extractRaw` take `ObjectSchema`, not a root string or list. An adapter given no `http.Client` creates and owns one; `Instructor.close` forwards to it. OpenAI-compatible servers (Ollama, LM Studio, vLLM, OpenRouter): `OpenAIAdapter(apiKey: 'ollama', model: 'llama3.2', baseUrl: 'http://localhost:11434/v1')`. Some ignore `tool_choice`; `extract` then parses JSON out of the text.

## Contracts

**Schema, both sides.** Build with `Schema.object` (properties required unless `.optional()`), plus `Schema.string` / `integer` / `number` / `boolean` / `enumeration` / `list`. `toJsonSchema()` is placed on `LlmRequest.jsonSchema` and the adapter sends it as the tool parameters (OpenAI `parameters`, Anthropic `input_schema`, Gemini `functionDeclarations.parameters`). The same object then `validate`s the decoded arguments and `normalize`s them. Do not also dump a JSON schema into the prompt.

**Repair loop.** `extract` / `extractRaw` call `LlmAdapter.complete` up to `maxRetries + 1` times (`maxRetries` defaults to 2, so three calls). Only schema misses retry; `AdapterException` propagates immediately. A miss appends `Message.assistant` (the payload that was judged) and `Message.user` (each `SchemaViolation`), then `onRetry`, unless this was the last attempt. After the last miss it throws.

**History.** `ExtractionException.attempts` is the full list of `ExtractionAttempt` (`number`, `violations`, `rawResponse`).

**Ints.** `jsonDecode('25.0')` is a `double` on the VM and an `int` on the web. `IntegerSchema.normalize` converts a finite integral `double` with `abs() <= 2^53` to `int` and leaves larger values as `double`. `NumberSchema.normalize` yields `double`. `fromJson` is not inside the repair loop: a bad cast there is a `TypeError`, not another attempt.

## Mistakes

- Root schema is not an object. Analyzer: `The argument type 'StringSchema' can't be assigned to the parameter type 'ObjectSchema'.` Wrap fields in `Schema.object`.
- `implements LlmAdapter`. Analyzer: `The class 'LlmAdapter' can't be implemented outside of its library because it's a base class.` Use `final class … extends LlmAdapter` and return `LlmResponse.toolCall` / `.text` / `.empty`.
- Model adds keys. `$.extra: unexpected property`. Default is `additionalProperties: false`; declare the keys or pass `allowAdditionalProperties: true`.
- HTTP or transport failure. `AdapterException(429): …` or `AdapterException(transport): request to the OpenAI API failed (…)` — not retried. Catch `AdapterException` separately from `ExtractionException`.
- `as int` on a `Schema.number()` field, or on an integer whose abs is `> 2^53`. `type 'double' is not a subtype of type 'int' in type cast`. Use `Schema.integer()` for ints; model snowflake ids as `Schema.string()` or read `num`.
- Required field omitted or sent as `null`. `$.name: required property is missing` / `$.name: expected a string, got null`. Mark `.optional()`; an explicit `null` on an optional property is treated as absent (forced tool calling fills unused parameters with `null`).
- `Schema.enumeration([])`. `Invalid argument (values): must not be empty`. `Schema.string(pattern: '(')`. `FormatException: Unterminated group (`.
- `maxRetries: -1`. `Invalid argument (maxRetries): must be >= 0: -1`. `maxRetries` is extra retries, not total calls.
- Anthropic request with only `Message.system`. `Invalid argument(s): request.messages must contain at least one non-system message`.
- Repairs exhausted. `ExtractionException: no valid response after N attempt(s). Last problems: $: response is not a JSON object` (or the last `SchemaViolation`s). Read `e.attempts`.

## Where things live

- `lib/instructor_dart.dart` — public exports
- `lib/src/instructor.dart` — `Instructor`, `ExtractionException`, `ExtractionAttempt`
- `lib/src/schema.dart` — `Schema`, `IntegerSchema.normalize`
- `lib/src/adapter.dart` — `LlmAdapter`, `LlmRequest`, `LlmResponse`, `AdapterException`
- `lib/src/adapters/` — `OpenAIAdapter`, `AnthropicAdapter`, `GeminiAdapter`
- `example/` — `no_model_demo.dart`, `mock_extract.dart`, and
  `with_stream_struct.dart` need no model and no network. The last is
  the join with `stream_struct` (a dev dependency): the object fills
  in as canned chunks arrive, then `extract` validates and, on a miss,
  retries.
- `test/` — unit tests; `test/ollama_e2e_test.dart` is `@Tags(['e2e'])` and skips without Ollama

```
dart analyze
dart test
dart run example/no_model_demo.dart
dart run example/with_stream_struct.dart
```
