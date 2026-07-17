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
