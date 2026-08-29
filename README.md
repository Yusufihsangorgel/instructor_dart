# instructor_dart

![instructor_dart banner](https://raw.githubusercontent.com/Yusufihsangorgel/instructor_dart/main/doc/banner.png)

Typed, validated structured outputs from LLMs.

![A terminal run of the extraction example: a sentence goes in, llama3.2:3b
answers locally, and a typed `Person(name: John Carmack, age: 55, city:
Dallas)` comes out rather than a `Map`](https://raw.githubusercontent.com/Yusufihsangorgel/instructor_dart/main/doc/local-extract.gif)

No model to hand? `dart run example/no_model_demo.dart` needs neither one nor a
network. Its adapter answers from a script: the first answer puts the age
outside the declared range, and you watch that rejection get written here and
quoted back before the second answer arrives. That loop is the package. The
same offline idea with a live-filling object is
`dart run example/with_stream_struct.dart`: tokens arrive, the object grows,
then `extract` validates the last frame and, on a miss, retries.

## Why this instead of what you already have

**Instead of parsing the reply yourself.** A forced tool call, `jsonDecode`, and
an if/else over the keys gets most of the way. Typing and repair are the tedious
parts. `IntegerSchema.normalize` (`lib/src/schema.dart:290`) collapses `25.0` to
`25` for an `integer` field, because `jsonDecode('25.0')` yields a `double` on
the VM and an `int` on the web, and it leaves values past 2^53 alone rather than
converting them lossily. On a violation, `extract` appends the model's own reply
and a repair prompt to the transcript and asks again
(`lib/src/instructor.dart:166`).

**Instead of `llm_schema`.** It validates the same kind of AI-generated JSON
with a similar Zod-style builder and path-aware errors, and it is a real,
adopted package, not a strawman: pure Dart, zero dependencies (`pubspec.yaml`
lists none), published a month before this comparison was written. What it
does not do is call a model. Its own README shows the retry as a hand-written
`for` loop that calls `callModel` a second time and re-parses the reply
(`README.md`, under "The repair loop"); nothing in its 1,206 lines of `lib/`
sends a request anywhere. `Instructor.extract` (`lib/src/instructor.dart:65`)
is that same loop, already wired to an adapter — OpenAI, Anthropic, or
Gemini — so a caller writes a schema and one call, not the retry itself.

**Also newer, worth naming honestly.** `typed_llm` reached pub.dev on
9 August 2026, three versions the same day, 0 likes and no 30-day download
count yet (`pub.dev/api/packages/typed_llm`). It takes a third road:
`build_runner` plus an `@LlmSchema` annotation that generates a `.g.dart`
(`README.md:66` and `:100`), where the schema here is a value you write at
runtime with no build step. Its `SchemaValidationException` carries the final
attempt's errors and a count (`lib/src/exceptions.dart:42-46`);
`ExtractionException.attempts` (`lib/src/instructor.dart:31`) carries every
attempt with its raw response.

**Instead of the provider's own structured-output mode.** That mode already
returns JSON of the right shape. A value can still be the wrong object: an
age of `999` is a JSON integer, `"root"` is a JSON string, and `25.0` is a
JSON Schema integer that Dart's VM will hand you as a `double`. This package
runs `validate` on the decoded value and, on a miss, quotes the problem back
for a retry (`lib/src/instructor.dart:166`). The table is those cases,
grounded in `validate` / `normalize`. A provider column is filled in only
when that provider's own documentation states the gap; where it does not,
the row is this package's behaviour only. No row is inferred from a live
model call.

| Case | Native JSON that still type-checks | This package | Native gap |
|---|---|---|---|
| Out-of-range number. `Schema.integer(min: 0, max: 130)`, value `999`. | A JSON integer. Wrong age. | `IntegerSchema` reports `expected <= 130, got 999` (`lib/src/schema.dart:285`). `extract` quotes that back (`lib/src/instructor.dart:166`). | **Cited.** Anthropic structured outputs strip `minimum` / `maximum` from the schema sent to the model and check the original constraints on the client ([structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)). OpenAI JSON mode "will not guarantee the output matches any specific schema, only that it is valid and parses without errors" ([JSON mode](https://platform.openai.com/docs/guides/structured-outputs#json-mode)). OpenAI Structured Outputs lists `minimum` / `maximum` as supported; this row does not claim they miss it. Gemini lists them as supported too, and still says to "always validate values in your application" ([structured outputs](https://ai.google.dev/gemini-api/docs/structured-output)). |
| Enum value outside the set. `Schema.enumeration(['admin', 'user'])`, value `"root"` — or the same letters with different capitalization. | A JSON string. | `EnumSchema` reports `expected one of admin, user, got …` (`lib/src/schema.dart:406`). Comparison is exact: `'Admin'` is not `'admin'`. | **Cited (Anthropic casing).** Anthropic: structured outputs "don't guarantee the capitalization of string `enum` values"; `"Conversation Topic 3"` can come back when the schema has `"Conversation topic 3"` ([structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)). OpenAI JSON mode: no schema, same citation as the row above. OpenAI Structured Outputs says you need not worry about "hallucinating an invalid enum value" ([structured outputs](https://platform.openai.com/docs/guides/structured-outputs)); this row does not contradict that. Gemini documents `enum` and still says to validate values. |
| Integer as `25.0` after `jsonDecode` on the VM. `Schema.integer()`, then `json['age'] as int`. | A JSON number with a zero fractional part — a JSON Schema integer. `jsonDecode('25.0')` is a `double` on the VM and an `int` on the web. | `IntegerSchema.validate` accepts both (`lib/src/schema.dart:270`). `normalize` then collapses a finite integral `double` with `abs() <= 2^53` to `int` (`lib/src/schema.dart:290`), so the `as int` in `fromJson` holds on both runtimes. Values past 2^53 stay a `double`. | **Package only.** Providers return JSON numbers. None of the three documents Dart's VM / web `jsonDecode` split. |

**Reach for it when**

- You are pulling fields out of unstructured text, such as an invoice or a
  scanned form, and the caller needs a typed object rather than a `Map`.
- A wrong type or a missing required field should cost one more model call, not
  a crash three layers down.
- You do not want a code generation step in the build.

Skip it if the model already returns clean JSON for your prompt and you are
happy hand-checking two or three fields, since a schema is only worth writing
once it is the thing doing the validating. Which constraints that schema
actually checks is in [What is actually validated](#what-is-actually-validated);
if the keyword you need is in the "not supported" list, this package will
not catch a miss.

Define the shape of the data you want as a plain-Dart schema, call
`extract`, and get back a validated Dart object. When the model returns
data that does not match the schema, the validation errors are sent back
to it and it gets another try.

No code generation, no build_runner. The schema is a value you write in
Dart, and the same definition is used twice: sent to the provider as a
tool signature, and used locally to validate what comes back.

```dart
import 'package:instructor_dart/instructor_dart.dart';

final instructor = Instructor(
  adapter: OpenAIAdapter(apiKey: apiKey, model: 'gpt-4o-mini'),
);
// An adapter given no http.Client creates and owns one. Close the
// Instructor when you are done with it; the call forwards to the adapter.
// A long-lived Instructor can simply live as long as the program.

final person = await instructor.extract(
  messages: const [Message.user('John Carmack is 55 and lives in Dallas.')],
  schema: Schema.object({
    'name': Schema.string(description: 'Full name'),
    'age': Schema.integer(min: 0, max: 130),
    'city': Schema.string().optional(),
  }),
  // Your model class, and your factory. The schema above describes the
  // shape; this turns the validated map into your type.
  fromJson: Person.fromJson,
);
// person is a Person. fromJson only runs after validation passed: every
// required field is present and correctly typed.
```

## How it works

1. Your schema is rendered to JSON Schema and sent as a forced
   tool/function call, which makes the model answer with data, not prose.
2. The response is validated locally against the same schema.
3. On failure, the violations (with JSONPath locations) are appended to
   the conversation and the model retries, up to `maxRetries` times.
4. If every attempt fails, `ExtractionException` carries the full attempt
   history: what the model said and why it was rejected.

A validated object is normalized to the Dart types its schema promises. An
`integer` field is an `int` even when the model wrote `25.0`, and a `number`
field is a `double` even when the model wrote a whole number like `42`, so
`json['age'] as int` and `json['price'] as double` behave the same on the Dart
VM and the web.

The one exception is an integral value beyond 2^53, where `double` can no
longer represent every integer: those are left as a `double` rather than
converted lossily, so `as int` would throw. If your field can hold a snowflake
id or a nanosecond timestamp, read it as `num` and convert deliberately, or
model it as a string.

![Diagram of the extract loop: prompt and schema go to the model as a forced tool call, the reply is parsed and validated, a mismatch is fed back for a retry, and a valid reply becomes a typed Dart object](https://raw.githubusercontent.com/Yusufihsangorgel/instructor_dart/main/doc/architecture.png)

```dart
try {
  final result = await instructor.extractRaw(
    messages: messages,
    schema: schema,
    maxRetries: 2,
    onRetry: (attempt) => log('attempt ${attempt.number}: '
        '${attempt.violations.join('; ')}'),
  );
} on ExtractionException catch (e) {
  // e.attempts[i].rawResponse and .violations tell you exactly what
  // happened on each try.
}
```

## Providers

| Adapter | Works with |
|---|---|
| `OpenAIAdapter` | OpenAI, and any OpenAI-compatible server: Ollama, LM Studio, vLLM, OpenRouter |
| `AnthropicAdapter` | Anthropic Messages API |
| `GeminiAdapter` | Gemini API `generateContent` |

```dart
final adapter = GeminiAdapter(
  apiKey: Platform.environment['GEMINI_API_KEY']!,
  model: 'gemini-2.0-flash',
);
```

Gemini differs from the other two in two ways the adapter takes care of. Its
`contents` only accepts the `user` and `model` roles, so an assistant message
is sent as `model`; and system text is not a message at all, it goes in the
top-level `systemInstruction`, where the adapter collects it. The schema is sent
as a function declaration and forced with `functionCallingConfig.mode: "ANY"`.
The API key travels in the `x-goog-api-key` header rather than the `key` query
parameter, which keeps it out of URLs and logs.

Local model via Ollama:

```dart
final adapter = OpenAIAdapter(
  apiKey: 'ollama', // any non-empty string
  model: 'llama3.2',
  baseUrl: 'http://localhost:11434/v1',
);
```

Note: some compatible servers, Ollama included, ignore `tool_choice` and
may answer with plain text. Extraction still works: the JSON is parsed
out of the text and validated the same way; a malformed answer costs one
repair round.

Anything else: extend `LlmAdapter` (one method to override) and pass it to
`Instructor`.

## Schema reference

| Builder | JSON Schema | Constraints |
|---|---|---|
| `Schema.string()` | `string` | `minLength`, `maxLength`, `pattern` |
| `Schema.integer()` | `integer` | `min`, `max` |
| `Schema.number()` | `number` | `min`, `max` |
| `Schema.boolean()` | `boolean` | |
| `Schema.enumeration([...])` | `string` + `enum` | |
| `Schema.list(items)` | `array` | `minItems`, `maxItems` |
| `Schema.object({...})` | `object` | `allowAdditionalProperties` |

Every builder takes a `description`; models read these when deciding what
to put in each field, and short concrete descriptions improve results.
Mark object properties with `.optional()` to leave them out of the
`required` list. Objects reject unexpected keys by default.

### What is actually validated

The provider's own structured-output mode already covers the simple
cases. This package is worth the dependency when the repair loop is
worth it, and only for constraints `validate` actually checks. A
keyword that looks enforced and is not is worse than one that is
missing. The cases where the JSON is well-typed and still the wrong
object — an out-of-range number, an enum member outside the set, an
integer that the VM left as a `double` — are in
[Instead of the provider's own structured-output mode](#why-this-instead-of-what-you-already-have).

**No constraint the builder lets you write is ignored at validate
time.** `description` is the only JSON Schema keyword this package
emits that `validate` does not check, and it is an annotation: the
model reads it, the validator does not.

`Schema.toJsonSchema()` (`lib/src/schema.dart:41`) is what every
bundled adapter sends as the tool parameters. `Schema.validate`
(`lib/src/schema.dart:44`) is what `extract` uses to decide whether
to retry. The two share one definition. "Sent" below means the
keyword appears in that JSON Schema; whether the provider also
enforces it is the provider's problem.

| Keyword | Written as | Local `validate` | Sent to the provider |
|---|---|---|---|
| `type` | every `Schema.*` | yes | yes |
| `description` | `description:` on every builder | no (annotation only) | yes |
| `minLength` | `Schema.string(minLength:)` | yes | yes |
| `maxLength` | `Schema.string(maxLength:)` | yes | yes |
| `pattern` | `Schema.string(pattern:)` | yes, unanchored Dart `RegExp.hasMatch` | yes |
| `minimum` | `Schema.integer(min:)` / `Schema.number(min:)` | yes, inclusive | yes |
| `maximum` | `Schema.integer(max:)` / `Schema.number(max:)` | yes, inclusive | yes |
| `enum` | `Schema.enumeration([...])` | yes, strings only | yes |
| `items` | `Schema.list(items)` | yes, one schema, not a tuple | yes |
| `minItems` | `Schema.list(..., minItems:)` | yes | yes |
| `maxItems` | `Schema.list(..., maxItems:)` | yes | yes |
| `properties` | `Schema.object({...})` | yes | yes |
| `required` | omit `.optional()` on a property | yes | yes, omitted when empty |
| `additionalProperties` | `allowAdditionalProperties:` | yes, boolean only | yes |

`minLength` / `maxLength` count Dart `String.length` (UTF-16 code
units), not JSON Schema's Unicode code-point count. One emoji is two
units.

These JSON Schema keywords cannot be written. They are not sent, and
`validate` does not implement them. That is not a silent ignore: the
builder has no parameter for them.

| Keyword | Notes |
|---|---|
| `format` | no `email`, `uri`, `date-time`, `uuid`, ... |
| `exclusiveMinimum`, `exclusiveMaximum` | `min` / `max` are inclusive `minimum` / `maximum` |
| `multipleOf` | |
| `uniqueItems` | duplicate list items pass |
| `contains`, `minContains`, `maxContains` | |
| `prefixItems`, `additionalItems`, `unevaluatedItems` | `items` is one schema |
| `patternProperties` | |
| `additionalProperties` as a schema | boolean only; `true` allows extra keys of any type |
| `minProperties`, `maxProperties` | |
| `dependentRequired`, `dependentSchemas`, `propertyNames` | |
| `unevaluatedProperties` | |
| `allOf`, `anyOf`, `oneOf`, `not` | no unions, no intersection |
| `if`, `then`, `else` | |
| `$ref`, `$defs`, `definitions` | no reuse by reference |
| `const` | use `Schema.enumeration` of one string |
| `type` as an array | no `nullable`, no `["string", "null"]`; optional is omit-from-`required` |
| `title`, `default`, `examples`, `$comment` | not emitted |

Putting a constraint in `description` does not make `validate` check
it. `Schema.string(description: 'RFC 5322 email')` accepts
`not-an-email`.

## Scope and roadmap

This package does one thing: reliable typed extraction. It is not an
agent framework and does not manage conversations, tools, or memory.

Streaming the object as tokens arrive is
[`stream_struct`](https://pub.dev/packages/stream_struct). This package
validates the finished value. `example/with_stream_struct.dart` is the
join, on canned chunks so it runs offline.

Planned: MCP sampling support, server-side strict schema modes (OpenAI
structured outputs, Anthropic strict tool use), and an optional bridge
for `json_serializable` classes.

## Credits

The extract-validate-retry pattern follows the `instructor` library from
the Python ecosystem, adapted to Dart idioms.

## License

MIT
