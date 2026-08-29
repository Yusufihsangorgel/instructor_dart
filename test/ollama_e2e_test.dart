@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:instructor_dart/instructor_dart.dart';
import 'package:test/test.dart';

/// End-to-end test against a local Ollama server.
///
/// Skipped automatically when no server is listening or the model is not
/// pulled. Run with:
///
///     ollama serve &
///     ollama pull llama3.2:3b
///     dart test test/ollama_e2e_test.dart
const _baseUrl = 'http://localhost:11434';
const _model = 'llama3.2:3b';

/// The reason to skip, or null when the server is up and [_model] is pulled.
Future<String?> _skipReason() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse('$_baseUrl/api/tags'));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      return 'No Ollama server at $_baseUrl.';
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final models = decoded['models'] as List<dynamic>? ?? const [];
    final names = [
      for (final model in models) (model as Map<String, dynamic>)['name'],
    ];
    if (!names.contains(_model)) {
      return 'Ollama is up at $_baseUrl but $_model is not pulled.';
    }
    return null;
  } on Exception {
    return 'No Ollama server at $_baseUrl.';
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('extracts typed data from a live local model', () async {
    final skip = await _skipReason();
    if (skip != null) {
      markTestSkipped(skip);
      return;
    }

    final adapter = OpenAIAdapter(
      apiKey: 'ollama',
      model: _model,
      baseUrl: '$_baseUrl/v1',
    );
    addTearDown(adapter.close);

    final raw = await Instructor(adapter: adapter).extractRaw(
      messages: const [
        Message.user(
          'Extract the person: "Grace Hopper was 85 years old and lived '
          'in Arlington."',
        ),
      ],
      schema: Schema.object({
        'name': Schema.string(description: 'Full name of the person'),
        'age': Schema.integer(min: 0, max: 130),
        'city': Schema.string(description: 'City they lived in').optional(),
      }),
      maxRetries: 3,
    );

    expect(raw['name'], contains('Hopper'));
    expect(raw['age'], 85);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
