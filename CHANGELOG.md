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
