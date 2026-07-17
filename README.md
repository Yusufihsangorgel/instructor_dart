# instructor_dart

![instructor_dart banner](https://raw.githubusercontent.com/Yusufihsangorgel/instructor_dart/main/doc/banner.png)

Typed, validated structured outputs from LLMs.

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

final person = await instructor.extract(
  messages: const [Message.user('John Carmack is 55 and lives in Dallas.')],
  schema: Schema.object({
    'name': Schema.string(description: 'Full name'),
    'age': Schema.integer(min: 0, max: 130),
    'city': Schema.string().optional(),
  }),
  fromJson: Person.fromJson,
);
// person is a Person. fromJson only runs after validation passed, so
// every required field is present and correctly typed.
```

## How it works

1. Your schema is rendered to JSON Schema and sent as a forced
   tool/function call, so the model answers with data, not prose.
2. The response is validated locally against the same schema.
3. On failure, the violations (with JSONPath locations) are appended to
   the conversation and the model retries, up to `maxRetries` times.
4. If every attempt fails, `ExtractionException` carries the full attempt
   history: what the model said and why it was rejected.

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

Anything else: implement `LlmAdapter` (one method) and pass it to
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
to put in each field, so short concrete descriptions improve results.
Mark object properties with `.optional()` to leave them out of the
`required` list. Objects reject unexpected keys by default.

## Scope and roadmap

This package does one thing: reliable typed extraction. It is not an
agent framework and does not manage conversations, tools, or memory.

Planned: streaming partial results, a Gemini adapter, MCP sampling
support, server-side strict schema modes (OpenAI structured outputs,
Anthropic strict tool use), and an optional bridge for
`json_serializable` classes.

## Credits

The extract-validate-retry pattern follows the `instructor` library from
the Python ecosystem, adapted to Dart idioms.

## License

MIT
