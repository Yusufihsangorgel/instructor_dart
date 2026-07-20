import 'dart:convert';

import 'package:http/http.dart' as http;

import '../adapter.dart';
import '../message.dart';

/// Adapter for the Gemini API's `generateContent` method.
///
/// The schema is sent as a function declaration and the call is forced with
/// `toolConfig.functionCallingConfig.mode = "ANY"` plus an
/// `allowedFunctionNames` of just that function, which is Gemini's equivalent
/// of OpenAI's `tool_choice`. When the model answers with plain text instead,
/// `Instructor` falls back to extracting JSON from it.
///
/// Two shapes differ from the other providers and are handled here:
/// Gemini's `contents` only accepts the `user` and `model` roles, so
/// [MessageRole.assistant] is sent as `model`; and system text is not a
/// message at all, it goes in the top-level `systemInstruction`, so every
/// [MessageRole.system] message is collected there.
///
/// The API key travels in the `x-goog-api-key` header rather than the `key`
/// query parameter, so it does not end up in URLs, proxy logs, or crash
/// reports. Both are accepted by the API.
final class GeminiAdapter implements LlmAdapter {
  /// [model] is the bare model id, such as `gemini-2.0-flash`; the adapter
  /// adds the `models/` prefix and the `:generateContent` suffix.
  ///
  /// [baseUrl] must point at the API version root that contains `models/`,
  /// which is `https://generativelanguage.googleapis.com/v1beta` by default.
  GeminiAdapter({
    required String apiKey,
    required this.model,
    String baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    http.Client? client,
    this.temperature,
    this.timeout = const Duration(seconds: 60),
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String model;
  final double? temperature;

  /// Per-request time limit. A `TimeoutException` is thrown when the server
  /// does not answer in time.
  final Duration timeout;

  final String _apiKey;
  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final systemText = [
      for (final message in request.messages)
        if (message.role == MessageRole.system) message.content,
    ].join('\n');

    final contents = [
      for (final message in request.messages)
        if (message.role != MessageRole.system)
          {
            'role': message.role == MessageRole.assistant ? 'model' : 'user',
            'parts': [
              {'text': message.content},
            ],
          },
    ];

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/models/$model:generateContent'),
          headers: {
            'x-goog-api-key': _apiKey,
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'contents': contents,
            if (systemText.isNotEmpty)
              'systemInstruction': {
                'parts': [
                  {'text': systemText},
                ],
              },
            'tools': [
              {
                'functionDeclarations': [
                  {
                    'name': request.toolName,
                    'description': request.toolDescription,
                    'parameters': request.jsonSchema,
                  },
                ],
              },
            ],
            'toolConfig': {
              'functionCallingConfig': {
                'mode': 'ANY',
                'allowedFunctionNames': [request.toolName],
              },
            },
            if (temperature != null)
              'generationConfig': {'temperature': temperature},
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
        response.statusCode,
        'response body is not JSON: $body',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw AdapterException(
        response.statusCode,
        'unexpected response shape: $body',
      );
    }

    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return const LlmResponse();
    final first = candidates.first;
    if (first is! Map<String, dynamic>) return const LlmResponse();
    final content = first['content'];
    if (content is! Map<String, dynamic>) return const LlmResponse();
    final parts = content['parts'] as List?;
    if (parts == null || parts.isEmpty) return const LlmResponse();

    // A forced call puts the arguments in a functionCall part. Take the first
    // one; text parts alongside it are commentary the caller does not need.
    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;
      final call = part['functionCall'];
      if (call is Map<String, dynamic>) {
        final arguments = call['args'];
        if (arguments is Map<String, dynamic>) {
          return LlmResponse(toolArguments: arguments.cast<String, Object?>());
        }
      }
    }

    // No call: hand back the text so the caller can try to repair it.
    final text = [
      for (final part in parts)
        if (part is Map<String, dynamic> && part['text'] is String)
          part['text'] as String,
    ].join();
    return LlmResponse(text: text.isEmpty ? null : text);
  }

  /// Closes the underlying HTTP client if this adapter created it.
  void close() {
    if (_ownsClient) _client.close();
  }
}
