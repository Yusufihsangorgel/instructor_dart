import 'dart:convert';

import 'package:http/http.dart' as http;

import '../adapter.dart';
import '../message.dart';

/// Adapter for the Anthropic Messages API.
///
/// The schema is sent as a tool and the tool call is forced with
/// `tool_choice`, so the model responds with structured data.
final class AnthropicAdapter implements LlmAdapter {
  AnthropicAdapter({
    required String apiKey,
    required this.model,
    this.maxTokens = 1024,
    String baseUrl = 'https://api.anthropic.com',
    String apiVersion = '2023-06-01',
    http.Client? client,
    this.temperature,
    this.timeout = const Duration(seconds: 60),
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _apiVersion = apiVersion,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String model;

  /// Required by the Messages API; raise it for large extractions. When
  /// the response is cut off at this limit, the adapter throws
  /// [AdapterException] instead of returning truncated data, because a
  /// retry under the same limit could never succeed.
  final int maxTokens;

  final double? temperature;

  /// Per-request time limit. A `TimeoutException` is thrown when the
  /// server does not answer in time.
  final Duration timeout;

  final String _apiKey;
  final String _baseUrl;
  final String _apiVersion;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    // The Messages API takes the system prompt as a top-level field, not as
    // a message.
    final system = request.messages
        .where((m) => m.role == MessageRole.system)
        .map((m) => m.content)
        .join('\n\n');
    final chat = [
      for (final message in request.messages)
        if (message.role != MessageRole.system)
          {'role': message.role.name, 'content': message.content},
    ];
    if (chat.isEmpty) {
      throw ArgumentError(
          'request.messages must contain at least one non-system message');
    }

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/v1/messages'),
          headers: {
            'x-api-key': _apiKey,
            'anthropic-version': _apiVersion,
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': maxTokens,
            if (temperature != null) 'temperature': temperature,
            if (system.isNotEmpty) 'system': system,
            'messages': chat,
            'tools': [
              {
                'name': request.toolName,
                'description': request.toolDescription,
                'input_schema': request.jsonSchema,
              },
            ],
            'tool_choice': {'type': 'tool', 'name': request.toolName},
          }),
        )
        .timeout(timeout);
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdapterException(response.statusCode, body);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw AdapterException(
          response.statusCode, 'response body is not JSON: $body');
    }
    if (decoded is! Map<String, dynamic>) {
      throw AdapterException(
          response.statusCode, 'unexpected response shape: $body');
    }
    final json = decoded;
    if (json['stop_reason'] == 'max_tokens') {
      throw AdapterException(
          response.statusCode,
          'response truncated at max_tokens=$maxTokens; '
          'raise AnthropicAdapter.maxTokens');
    }
    final content = json['content'] as List?;
    if (content == null) return const LlmResponse();

    for (final block in content) {
      if (block is Map<String, dynamic> && block['type'] == 'tool_use') {
        final input = block['input'];
        if (input is Map<String, dynamic>) {
          return LlmResponse(toolArguments: input.cast<String, Object?>());
        }
      }
    }
    final text = [
      for (final block in content)
        if (block is Map<String, dynamic> && block['type'] == 'text')
          block['text'] as String? ?? '',
    ].join();
    return LlmResponse(text: text.isEmpty ? null : text);
  }

  /// Closes the underlying HTTP client if this adapter created it.
  void close() {
    if (_ownsClient) _client.close();
  }
}
