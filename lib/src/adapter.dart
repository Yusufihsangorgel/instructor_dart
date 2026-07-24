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

/// The error type every adapter reports, so a caller can write a single
/// `on AdapterException catch (e)` around a `complete` call.
///
/// It covers three ways a request can fail: the provider answered with a non-2xx
/// status, the provider answered 2xx but with a body this adapter could not make
/// sense of, and the request never got an answer at all (the connection dropped,
/// timed out, or the client was closed). The last of those has no status code,
/// which is why [statusCode] is nullable and [AdapterException.transport] exists.
final class AdapterException implements Exception {
  /// A response arrived, but it was an error status or a shape the adapter
  /// could not read. [statusCode] is the HTTP status.
  const AdapterException(int this.statusCode, this.body, {this.cause});

  /// No usable response arrived: the connection failed, timed out, or the
  /// client was already closed. There is no [statusCode].
  const AdapterException.transport(this.body, {this.cause}) : statusCode = null;

  /// The HTTP status, or `null` when the failure was at the transport layer
  /// (see [AdapterException.transport]).
  final int? statusCode;

  /// A human-readable description of what went wrong, including the response
  /// body where there was one.
  final String body;

  /// The underlying error this wraps, when there was one — a `SocketException`
  /// from a dropped connection, a `TypeError` from an unexpected response shape.
  /// Kept for logging; its type is deliberately not part of the contract, so do
  /// not switch on it.
  final Object? cause;

  @override
  String toString() {
    final where = statusCode == null ? 'transport' : '$statusCode';
    final why = cause == null ? '' : ' ($cause)';
    return 'AdapterException($where): $body$why';
  }
}
