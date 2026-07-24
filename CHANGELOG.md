## 1.0.0

The API is stable. One freeze-cleanliness gap was found by adversarially testing
the package rather than reading it, and it is fixed here.

- **`LlmRequest` now copies its `messages` and `jsonSchema`.** They aliased the
  list and map you passed in, so mutating them afterwards changed a request an
  adapter was about to send. They are now copied to unmodifiable collections
  (matching `Schema.enumeration`, which already copied its values). The
  constructor is no longer `const`, which is only breaking for a `const
  LlmRequest(...)` call — impossible in practice, since the messages and schema
  are runtime values.

Everything else was verified by execution and left unchanged: a 2xx response
with an unexpected nested shape becomes an `AdapterException` (not a raw
`TypeError`), a transport failure becomes `AdapterException.transport`, an
extraction that fails every retry throws `ExtractionException` carrying the
attempt history, `close()` is idempotent, and schema validation rejects a wrong
type, an out-of-range integer, a missing required field, and an unknown field.
`LlmAdapter` is a growable `abstract base class` so streaming can be added
later without breaking implementers; the only runtime dependency is `http`.

## 0.7.1

- Add `example/mock_extract.dart` and `example/README.md`. The Example tab was
  empty, and both existing examples need a live model. The new one uses a
  scripted `MockClient` — the model returns an out-of-range value first, so it
  runs the schema-validation-then-retry loop, the package's core, with no
  network. Docs and example only.

## 0.7.0

Settles the adapter error contract before 1.0.0. Breaking because
`AdapterException` grew a field and its `statusCode` is now nullable; the
migration is small.

- **Every adapter failure is now an `AdapterException`.** A 2xx response whose
  nested shape was not what a spec-compliant server sends used to escape as a
  raw `TypeError` the caller could not catch by type — and an OpenAI-compatible
  server (Ollama, LM Studio, vLLM, OpenRouter) is exactly where odd shapes turn
  up. Reproduced across four shapes (choices as an object, choices[0] as a
  string, tool_calls[0] as a number, a content part's text as a number); all
  four now throw `AdapterException` with the original `TypeError` on `.cause`.
- **Transport failures are an `AdapterException` too.** A dropped connection,
  a timeout, or a closed client used to surface as `SocketException`,
  `TimeoutException` or `http.ClientException`. They now become
  `AdapterException.transport`, whose `statusCode` is `null` (there was no
  response) and whose `.cause` is the underlying error.
- `AdapterException` gained a `cause` and a nullable `statusCode`. Both had to
  land before 1.0.0: adding a field or a "no status code" case to a frozen
  exception would be a breaking change. If you read `e.statusCode` as
  non-nullable, handle the transport `null`; the previous fields are unchanged.
- Document `Schema.normalize`'s contract: it assumes a validated value and
  passes non-conforming input through rather than throwing (verified — it does
  not crash on unvalidated input), and it leaves an integer beyond 2^53 as a
  `double`, matching the README.

## 0.6.0

Two pre-1.0.0 decisions, both about what the API promises rather than what it
computes. Breaking for anyone who wrote their own adapter; the migration is one
word.

- **`LlmAdapter` is now an `abstract base class` with a `close()` default, and
  `Instructor` has a `close()` that forwards to it.** Two problems met here.
  An adapter constructed without an `http.Client` creates one and owns it, and
  the shape the README leads with passes the adapter inline and never keeps a
  reference — so nothing could reach that client, and a program following the
  README sat on an idle socket after its work was done. `close()` existed only
  on the three concrete adapters, not on the type callers hold. The second
  problem is that fixing this by adding a member to an `abstract interface
  class` breaks every third-party implementer, and the roadmap has streaming on
  it, which would break them a second time. A `base` class with concrete
  defaults can grow without breaking anyone, so that is what it is now.

  To migrate, change `implements LlmAdapter` to `extends LlmAdapter` and mark
  your class `base`, `final` or `sealed`. Override `close()` only if your
  adapter owns something.

- **Corrected the integer claim in the README.** It said `json['age'] as int`
  is always safe for an `integer` field. It is not, above 2^53: `validate`
  accepts such a value, but `normalize` deliberately leaves it a `double`
  rather than converting lossily, so the cast throws. Measured: `1e16`, `1e17`
  and `1e300` all validate and all throw on `as int`. The README now says so
  and suggests reading such a field as `num`, or modelling it as a string.

## 0.5.0

The last things to settle before this can freeze at 1.0.0, all found by
re-reviewing the public surface against what a permanent contract would fix.

- Stop `Schema.object` aliasing the caller's map. It stored the exact map
  passed in, so `Schema.object(props)` followed by `props['x'] = ...` changed
  the schema afterwards, and `schema.properties` was itself writable, both
  bypassing every check the factory does and changing what `validate` demands.
  This is the same escape hatch 0.4.0 closed for the constructors, left open in
  one more place. `Schema.object` now copies into an unmodifiable map, matching
  what `Schema.enumeration` already documents and does for its list. Breaking
  only for code that mutated a schema through that aliasing, which was never
  intended to work.
- Make `collectViolations` private. It was public with a note that it had to
  be, "so that schema types can recurse into each other". That was not true:
  `Schema` is `sealed` and every schema type lives in the one library, so the
  recursion works with it private, and Dart privacy is per-library. Public, it
  froze an internal accumulator hook, its out-parameter list and its
  seed-the-path convention, into the 1.0.0 contract. `validate` is the
  supported entry point and is unchanged.
- Give `SchemaViolation` and `Message` value equality. Both are small
  immutable value types that callers naturally compare and put in sets:
  deduplicating the violations across `ExtractionException.attempts`, or
  asserting on `LlmRequest.messages` in an adapter test. `Message` was worse
  than missing equality, it was inconsistent: two `const` identical messages
  compared equal through canonicalization while two runtime-built identical
  ones did not. Both now compare by value. Adding this after 1.0.0 would
  silently change how existing sets and maps of these types dedup, so it lands
  now.

## 0.4.0

- Make the concrete schema constructors library-private so the validating
  `Schema.*` factories are the only way to build a schema. Breaking change:
  `StringSchema(...)`, `IntegerSchema(...)`, `NumberSchema(...)`,
  `BooleanSchema(...)`, `EnumSchema(...)`, `ListSchema(...)` and
  `ObjectSchema(...)` can no longer be called directly; use `Schema.string`,
  `Schema.integer`, `Schema.number`, `Schema.boolean`, `Schema.enumeration`,
  `Schema.list` and `Schema.object` instead. The concrete types stay exported
  for use in return types, `switch`, and field access, and `.optional()`
  still returns the same concrete type. This closes a construction path that
  skipped the factory checks: `Schema.string` rejects an invalid regular
  expression and `Schema.enumeration` rejects an empty list and copies its
  values, and a direct constructor call bypassed both.

## 0.3.1

- Fix `.optional()` rejecting an explicit JSON `null` on the property it was
  applied to. `.optional()` only removed the key from the JSON Schema
  `required` list, so a key present with value `null` still fell through to
  the leaf schema's type check and failed as a type mismatch instead of being
  treated as absent. Forced tool calling on OpenAI, Anthropic and Gemini
  regularly fills in every declared parameter and represents "no value" as
  `null` rather than omitting the key, so this broke `.optional()` for
  exactly the case it exists for. A required property given `null` is still
  reported as a violation.

## 0.3.0

- Normalize numeric fields to the Dart type their schema promises instead of
  coercing every integral double to `int`. A `number` field given a whole
  value like `42` now decodes to a `double` (`42.0`), so `json['price'] as
  double` in `fromJson` no longer throws after validation reported success; an
  `integer` field still arrives as `int`. Adds `Schema.normalize`, called after
  validation to do this per node type.

## 0.2.3

- Shorten the screenshot description. pub.dev accepts up to 200 characters but
  scores only those under 160, so the previous release published cleanly and
  quietly gave up the documentation points it was meant to earn.

## 0.2.2

- Declare the diagram in `pubspec.yaml` so pub.dev renders it on the package
  page. It was already in the repository and the README, but pub.dev shows only
  what the `screenshots:` field points at.

## 0.2.1

- Shorten the pub.dev description back under the 180-character limit. The
  previous release grew it past that, which costs the "valid pubspec" points
  and truncates the text search engines show.

## 0.2.0

- Add `GeminiAdapter` for the Gemini API's `generateContent`, completing the
  three major providers. The schema is sent as a function declaration and
  forced with `functionCallingConfig.mode: "ANY"`. Two Gemini-specific shapes
  are handled: `contents` only accepts the `user` and `model` roles, so an
  assistant message is sent as `model`, and system text goes in the top-level
  `systemInstruction` rather than being a message. The API key is sent in the
  `x-goog-api-key` header instead of the `key` query parameter, so it stays out
  of URLs and logs.

## 0.1.2

- Docs: tightened the README wording and visuals.

## 0.1.1

- Expand the package description to name what the package does in the
  words people search for. No code changes.

## 0.1.0

Initial release.

- Plain-Dart schema builder rendering to JSON Schema: objects, strings,
  integers, numbers, booleans, enums, lists, nesting, optional properties,
  length/range/pattern constraints.
- Local validation with JSONPath-style violation reporting.
- `Instructor.extract` / `extractRaw` with an automatic repair loop that
  feeds validation errors back to the model.
- `OpenAIAdapter` for OpenAI and OpenAI-compatible servers (Ollama,
  LM Studio, vLLM, OpenRouter), using forced tool calls.
- `AnthropicAdapter` for the Anthropic Messages API, using forced tool use.
- `ExtractionException` with full attempt history.
