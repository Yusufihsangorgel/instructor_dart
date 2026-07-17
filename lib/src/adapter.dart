import 'message.dart';

/// A provider-agnostic completion request.
///
/// Adapters translate this into the provider's wire format. The schema is
/// presented to the model as a tool/function call named [toolName], forced
/// via the provider's tool-choice mechanism where the server supports it.
final class LlmRequest {
  const LlmRequest({
    required this.messages,
    required this.toolName,
    required this.toolDescription,
    required this.jsonSchema,
  });

  final List<Message> messages;
  final String toolName;
  final String toolDescription;

  /// JSON Schema for the tool parameters, produced by `Schema.toJsonSchema()`.
  final Map<String, Object?> jsonSchema;
}

/// A provider-agnostic completion response.
///
/// Adapters must set at most one of the two fields. When the provider
/// returned a parsed tool call, [toolArguments] carries it; when it
/// returned plain text (or an unparseable tool call), [text] carries that
/// and the caller falls back to extracting JSON from it.
final class LlmResponse {
  const LlmResponse({this.toolArguments, this.text});

  final Map<String, Object?>? toolArguments;
  final String? text;
}

/// Bridge between [LlmRequest] and one provider's HTTP API.
///
/// Implement this to add a provider. Implementations should throw
/// [AdapterException] on non-2xx responses and otherwise return whatever the
/// model produced without judging it; validation and retries happen upstream.
abstract interface class LlmAdapter {
  Future<LlmResponse> complete(LlmRequest request);
}

/// Error from the provider's HTTP API (non-2xx response).
final class AdapterException implements Exception {
  const AdapterException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'AdapterException($statusCode): $body';
}
