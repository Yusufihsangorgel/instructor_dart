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
