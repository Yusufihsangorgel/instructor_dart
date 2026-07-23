import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instructor_dart/instructor_dart.dart';
import 'package:test/test.dart';

LlmRequest _request() => LlmRequest(
      messages: const [
        Message.system('Be precise.'),
        Message.user('John is 25.'),
        Message.assistant('Understood.'),
      ],
      toolName: 'extract',
      toolDescription: 'Record the extracted data.',
      jsonSchema: Schema.object({'name': Schema.string()}).toJsonSchema(),
    );

http.Response _functionCallResponse(Map<String, Object?> args) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {'name': 'extract', 'args': args},
                },
              ],
              'role': 'model',
            },
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('GeminiAdapter', () {
    test('builds a forced function call in Gemini\'s documented shape',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _functionCallResponse({'name': 'John'});
      });

      final adapter = GeminiAdapter(
        apiKey: 'secret',
        model: 'gemini-2.0-flash',
        client: client,
      );
      final response = await adapter.complete(_request());

      // Endpoint: models/<model>:generateContent under the version root.
      expect(
        captured.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent',
      );
      // The key goes in the header, so it never lands in a URL or a log.
      expect(captured.headers['x-goog-api-key'], 'secret');
      expect(captured.url.query, isEmpty);

      final body = jsonDecode(captured.body) as Map<String, dynamic>;

      // System text is not a message in Gemini; it is systemInstruction.
      expect(
        (body['systemInstruction'] as Map)['parts'],
        [
          {'text': 'Be precise.'},
        ],
      );

      // contents carries only user and model roles, in order.
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'John is 25.'},
          ],
        },
        {
          'role': 'model',
          'parts': [
            {'text': 'Understood.'},
          ],
        },
      ]);

      // The schema rides as a function declaration, forced with mode ANY.
      final declaration = ((body['tools'] as List).first
          as Map)['functionDeclarations'] as List;
      expect((declaration.first as Map)['name'], 'extract');
      expect((declaration.first as Map)['description'],
          'Record the extracted data.');
      expect((declaration.first as Map)['parameters'],
          Schema.object({'name': Schema.string()}).toJsonSchema());
      final config =
          (body['toolConfig'] as Map)['functionCallingConfig'] as Map;
      expect(config['mode'], 'ANY');
      expect(config['allowedFunctionNames'], ['extract']);

      // And the call's args come back as the tool arguments.
      expect(response.toolArguments, {'name': 'John'});
      expect(response.text, isNull);
    });

    test('omits systemInstruction when there is no system message', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _functionCallResponse(const {'name': 'Ada'});
      });
      final adapter = GeminiAdapter(
        apiKey: 'k',
        model: 'gemini-2.0-flash',
        client: client,
      );
      await adapter.complete(
        LlmRequest(
          messages: const [Message.user('Ada is 36.')],
          toolName: 'extract',
          toolDescription: 'Record it.',
          jsonSchema: Schema.object({'name': Schema.string()}).toJsonSchema(),
        ),
      );
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('systemInstruction'), isFalse);
    });

    test('joins several system messages into one instruction', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _functionCallResponse(const {'name': 'x'});
      });
      final adapter = GeminiAdapter(
        apiKey: 'k',
        model: 'gemini-2.0-flash',
        client: client,
      );
      await adapter.complete(
        LlmRequest(
          messages: const [
            Message.system('Be precise.'),
            Message.system('Answer in English.'),
            Message.user('Go.'),
          ],
          toolName: 'extract',
          toolDescription: 'Record it.',
          jsonSchema: Schema.object({'name': Schema.string()}).toJsonSchema(),
        ),
      );
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect((body['systemInstruction'] as Map)['parts'], [
        {'text': 'Be precise.\nAnswer in English.'},
      ]);
    });

    test('falls back to text when the model answers without a call', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"name":'},
                    {'text': '"John"}'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final adapter = GeminiAdapter(
        apiKey: 'k',
        model: 'gemini-2.0-flash',
        client: client,
      );
      final response = await adapter.complete(_request());
      // Text parts are concatenated so a split JSON body survives.
      expect(response.text, '{"name":"John"}');
      expect(response.toolArguments, isNull);
    });

    test('prefers the function call when text sits alongside it', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Here you go:'},
                    {
                      'functionCall': {
                        'name': 'extract',
                        'args': {'name': 'John'},
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final adapter = GeminiAdapter(
        apiKey: 'k',
        model: 'gemini-2.0-flash',
        client: client,
      );
      final response = await adapter.complete(_request());
      expect(response.toolArguments, {'name': 'John'});
    });

    test('a non-2xx response throws AdapterException', () async {
      final client = MockClient((request) async {
        return http.Response('{"error":{"message":"bad key"}}', 403);
      });
      final adapter = GeminiAdapter(
        apiKey: 'k',
        model: 'gemini-2.0-flash',
        client: client,
      );
      await expectLater(
        adapter.complete(_request()),
        throwsA(isA<AdapterException>()
            .having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an empty candidate list yields an empty response', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'candidates': []}), 200),
      );
      final adapter = GeminiAdapter(
        apiKey: 'k',
        model: 'gemini-2.0-flash',
        client: client,
      );
      final response = await adapter.complete(_request());
      expect(response.toolArguments, isNull);
      expect(response.text, isNull);
    });

    test('a trailing slash on baseUrl does not double up', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _functionCallResponse(const {'name': 'x'});
      });
      final adapter = GeminiAdapter(
        apiKey: 'k',
        model: 'gemini-2.0-flash',
        baseUrl: 'https://example.test/v1beta/',
        client: client,
      );
      await adapter.complete(_request());
      expect(
        captured.url.toString(),
        'https://example.test/v1beta/models/gemini-2.0-flash:generateContent',
      );
    });
  });
}
