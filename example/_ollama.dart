// Checks that a local model is reachable before an example tries to use one.
//
// Without this the examples end in an unhandled exception and a stack trace
// pointing into this package, which reads like the package is broken. The
// reader's actual problem is that nothing is listening on 11434, and the fix
// is one command. Say that instead.
import 'dart:convert';
import 'dart:io';

/// Where Ollama listens, overridable for anyone running it elsewhere.
final String ollamaHost = Platform.environment['OLLAMA_HOST'] ?? 'localhost';
final int ollamaPort =
    int.tryParse(Platform.environment['OLLAMA_PORT'] ?? '') ?? 11434;

/// The model the examples ask for. Small on purpose: this is a demonstration
/// of the extraction contract, not of how good the model is. Override it if
/// you already have something else pulled.
final String ollamaModel =
    Platform.environment['OLLAMA_MODEL'] ?? 'llama3.2:3b';

/// Base URL for the OpenAI-compatible endpoint Ollama serves.
String get ollamaBaseUrl => 'http://$ollamaHost:$ollamaPort/v1';

const String _seeItWithoutAModel =
    'To see the extraction contract without a model at all, run\n'
    '  dart run example/no_model_demo.dart';

/// Exits with a usable message when no model is reachable.
///
/// Two separate things go wrong here and they need different instructions:
/// nothing is listening, or something is listening but the model was never
/// pulled. Reporting the second as the first sends the reader off to start a
/// server that is already running.
Future<void> requireOllama() async {
  try {
    final socket = await Socket.connect(
      ollamaHost,
      ollamaPort,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
  } on SocketException {
    stderr.writeln(
      'This example needs Ollama listening on $ollamaHost:$ollamaPort.\n'
      '  brew install ollama && ollama serve\n'
      '  ollama pull $ollamaModel\n'
      'Set OLLAMA_HOST or OLLAMA_PORT if yours is somewhere else.\n'
      '\n'
      '$_seeItWithoutAModel',
    );
    exit(69); // EX_UNAVAILABLE
  }

  final available = await _installedModels();
  // An empty list means the check itself did not work. Let the request go
  // through rather than blocking on a check that cannot answer.
  if (available.isEmpty || available.contains(ollamaModel)) return;

  // Only suggest models that could actually do this. An embedding model is
  // listed alongside the rest and cannot answer a tool call, so proposing one
  // sends the reader to a second, more confusing failure.
  final usable = available.where((m) => !m.contains('embed')).toList();

  stderr.writeln(
    'Ollama is running on $ollamaHost:$ollamaPort but "$ollamaModel" is not '
    'pulled.\n'
    '  ollama pull $ollamaModel\n'
    '${usable.isEmpty ? '' : 'Or use one you already have, '
        '${usable.join(', ')}:\n'
        '  OLLAMA_MODEL=${usable.first} dart run $_script\n'}'
    '\n'
    '$_seeItWithoutAModel',
  );
  exit(69); // EX_UNAVAILABLE
}

/// The script being run, so the suggested command is the one that failed.
String get _script {
  final path = Platform.script.toFilePath();
  final i = path.indexOf('/example/');
  return i < 0 ? path : path.substring(i + 1);
}

Future<List<String>> _installedModels() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri.parse('$ollamaBaseUrl/models'));
    final response = await request.close();
    if (response.statusCode != 200) return const [];
    final body = await response.transform(utf8.decoder).join();
    final data = (jsonDecode(body) as Map<String, Object?>)['data'];
    if (data is! List) return const [];
    return [
      for (final entry in data)
        if (entry is Map<String, Object?> && entry['id'] is String)
          entry['id']! as String,
    ];
  } on Object {
    // A check that cannot answer must not be the thing that stops the run.
    return const [];
  } finally {
    client.close(force: true);
  }
}
