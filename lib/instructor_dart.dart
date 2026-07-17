/// Typed, validated structured outputs from LLMs.
///
/// Define the shape of the data you want with [Schema], call
/// [Instructor.extract], and get back a validated Dart object. Responses
/// that do not match the schema are sent back to the model with the
/// validation errors, and it gets another try.
library;

export 'src/adapter.dart'
    show AdapterException, LlmAdapter, LlmRequest, LlmResponse;
export 'src/adapters/anthropic_adapter.dart' show AnthropicAdapter;
export 'src/adapters/openai_adapter.dart' show OpenAIAdapter;
export 'src/instructor.dart'
    show ExtractionAttempt, ExtractionException, Instructor;
export 'src/message.dart' show Message, MessageRole;
export 'src/schema.dart'
    show
        BooleanSchema,
        EnumSchema,
        IntegerSchema,
        ListSchema,
        NumberSchema,
        ObjectSchema,
        Schema,
        SchemaViolation,
        StringSchema;
