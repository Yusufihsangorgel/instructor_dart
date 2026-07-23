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
