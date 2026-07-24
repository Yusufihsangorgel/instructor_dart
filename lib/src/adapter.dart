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
/// Extend this to add a provider. Subclasses should throw [AdapterException]
/// on non-2xx responses and otherwise return whatever the model produced
/// without judging it; validation and retries happen upstream.
///
/// It is a `base` class rather than an interface so that it can grow. A method
/// added here with a default body reaches every adapter without breaking it,
/// which is what lets planned work (streaming, sampling) land in a minor
/// release instead of a major one. Subclasses must themselves be `base`,
/// `final` or `sealed`.
abstract base class LlmAdapter {
  const LlmAdapter();

  Future<LlmResponse> complete(LlmRequest request);

  /// Releases anything the adapter owns, typically the HTTP client it created
  /// when the caller did not supply one.
  ///
  /// The default does nothing, so an adapter that borrows its transport need
  /// not override it. Safe to call more than once. [Instructor.close] forwards
  /// here, so a caller that only holds an `Instructor` can still release the
  /// socket.
  void close() {}
}

/// Error from the provider's HTTP API (non-2xx response).
final class AdapterException implements Exception {
  const AdapterException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'AdapterException($statusCode): $body';
}
