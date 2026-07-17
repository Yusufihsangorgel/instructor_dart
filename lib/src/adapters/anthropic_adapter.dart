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
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _apiVersion = apiVersion,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String model;

  /// Required by the Messages API; raise it for large extractions.
  final int maxTokens;

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

    final response = await _client.post(
      Uri.parse('$_baseUrl/v1/messages'),
      headers: {
        'x-api-key': _apiKey,
        'anthropic-version': _apiVersion,
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        if (system.isNotEmpty) 'system': system,
        'messages': [
          for (final message in request.messages)
            if (message.role != MessageRole.system)
              {'role': message.role.name, 'content': message.content},
        ],
        'tools': [
          {
            'name': request.toolName,
            'description': request.toolDescription,
            'input_schema': request.jsonSchema,
          },
        ],
        'tool_choice': {'type': 'tool', 'name': request.toolName},
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdapterException(
          response.statusCode, utf8.decode(response.bodyBytes));
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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
