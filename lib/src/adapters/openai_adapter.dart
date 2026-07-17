import 'dart:convert';

import 'package:http/http.dart' as http;

import '../adapter.dart';

/// Adapter for the OpenAI Chat Completions API and compatible servers
/// (Ollama, LM Studio, vLLM, OpenRouter, and others exposing `/v1`).
///
/// The schema is sent as a function tool and the tool call is forced with
/// `tool_choice`, so the model cannot answer with prose instead of data.
final class OpenAIAdapter implements LlmAdapter {
  /// [baseUrl] must point at the API root that contains
  /// `/chat/completions`, e.g. `https://api.openai.com/v1` or
  /// `http://localhost:11434/v1` for Ollama.
  OpenAIAdapter({
    required String apiKey,
    required this.model,
    String baseUrl = 'https://api.openai.com/v1',
    http.Client? client,
    this.temperature,
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String model;
  final double? temperature;
  final String _apiKey;
  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'authorization': 'Bearer $_apiKey',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        if (temperature != null) 'temperature': temperature,
        'messages': [
          for (final message in request.messages)
            {'role': message.role.name, 'content': message.content},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': request.toolName,
              'description': request.toolDescription,
              'parameters': request.jsonSchema,
            },
          },
        ],
        'tool_choice': {
          'type': 'function',
          'function': {'name': request.toolName},
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdapterException(
          response.statusCode, utf8.decode(response.bodyBytes));
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      return const LlmResponse();
    }
    final message =
        (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    if (message == null) return const LlmResponse();

    final toolCalls = message['tool_calls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty) {
      final function = (toolCalls.first as Map<String, dynamic>)['function']
          as Map<String, dynamic>?;
      final arguments = function?['arguments'];
      if (arguments is String) {
        try {
          final decoded = jsonDecode(arguments);
          if (decoded is Map<String, dynamic>) {
            return LlmResponse(toolArguments: decoded.cast<String, Object?>());
          }
        } on FormatException {
          // Malformed arguments; fall through and let the caller repair.
        }
        return LlmResponse(text: arguments);
      }
    }
    return LlmResponse(text: message['content'] as String?);
  }

  /// Closes the underlying HTTP client if this adapter created it.
  void close() {
    if (_ownsClient) _client.close();
  }
}
