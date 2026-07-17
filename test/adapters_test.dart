import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instructor_dart/instructor_dart.dart';
import 'package:test/test.dart';

LlmRequest _request() => LlmRequest(
      messages: const [
        Message.system('Be precise.'),
        Message.user('John is 25.'),
      ],
      toolName: 'extract',
      toolDescription: 'Record the extracted data.',
      jsonSchema: Schema.object({'name': Schema.string()}).toJsonSchema(),
    );

void main() {
  group('OpenAIAdapter', () {
    test('builds a forced tool call request and parses the response', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'type': 'function',
                      'function': {
                        'name': 'extract',
                        'arguments': '{"name":"John"}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final adapter =
          OpenAIAdapter(apiKey: 'key', model: 'test-model', client: client);
      final response = await adapter.complete(_request());

      expect(response.toolArguments, {'name': 'John'});
      expect(captured.url.toString(),
          'https://api.openai.com/v1/chat/completions');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'test-model');
      expect(body['tool_choice'], {
        'type': 'function',
        'function': {'name': 'extract'},
      });
      expect(body['messages'], [
        {'role': 'system', 'content': 'Be precise.'},
        {'role': 'user', 'content': 'John is 25.'},
      ]);
      final tool = ((body['tools'] as List).single
          as Map<String, dynamic>)['function'] as Map<String, dynamic>;
      expect(tool['parameters'], containsPair('type', 'object'));
    });

    test('supports OpenAI-compatible base URLs', () async {
      late Uri captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response(jsonEncode({'choices': []}), 200);
      });
      final adapter = OpenAIAdapter(
        apiKey: 'unused',
        model: 'llama3.2',
        baseUrl: 'http://localhost:11434/v1/',
        client: client,
      );
      await adapter.complete(_request());
      expect(captured.toString(), 'http://localhost:11434/v1/chat/completions');
    });

    test('returns malformed tool arguments as text for repair', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'function': {'name': 'extract', 'arguments': '{oops'},
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          ));
      final adapter = OpenAIAdapter(apiKey: 'key', model: 'm', client: client);
      final response = await adapter.complete(_request());
      expect(response.toolArguments, isNull);
      expect(response.text, '{oops');
    });

    test('throws AdapterException on non-2xx responses', () async {
      final client =
          MockClient((request) async => http.Response('rate limited', 429));
      final adapter = OpenAIAdapter(apiKey: 'key', model: 'm', client: client);
      await expectLater(
        adapter.complete(_request()),
        throwsA(isA<AdapterException>()
            .having((e) => e.statusCode, 'statusCode', 429)),
      );
    });
  });

  group('AnthropicAdapter', () {
    test('lifts system messages and parses tool_use blocks', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'content': [
              {
                'type': 'tool_use',
                'name': 'extract',
                'input': {'name': 'John'},
              },
            ],
          }),
          200,
        );
      });

      final adapter =
          AnthropicAdapter(apiKey: 'key', model: 'test-model', client: client);
      final response = await adapter.complete(_request());

      expect(response.toolArguments, {'name': 'John'});
      expect(captured.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(captured.headers['x-api-key'], 'key');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['system'], 'Be precise.');
      expect(body['messages'], [
        {'role': 'user', 'content': 'John is 25.'},
      ]);
      expect(body['tool_choice'], {'type': 'tool', 'name': 'extract'});
      expect(body['max_tokens'], 1024);
      final tool = (body['tools'] as List).single as Map<String, dynamic>;
      expect(tool['input_schema'], containsPair('type', 'object'));
    });

    test('falls back to concatenated text blocks', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': '{"name":'},
                {'type': 'text', 'text': ' "John"}'},
              ],
            }),
            200,
          ));
      final adapter =
          AnthropicAdapter(apiKey: 'key', model: 'm', client: client);
      final response = await adapter.complete(_request());
      expect(response.text, '{"name": "John"}');
    });

    test('throws AdapterException on non-2xx responses', () async {
      final client =
          MockClient((request) async => http.Response('overloaded', 529));
      final adapter =
          AnthropicAdapter(apiKey: 'key', model: 'm', client: client);
      await expectLater(
        adapter.complete(_request()),
        throwsA(isA<AdapterException>()
            .having((e) => e.statusCode, 'statusCode', 529)),
      );
    });

    test('throws when the response was truncated at max_tokens', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'stop_reason': 'max_tokens',
              'content': [
                {
                  'type': 'tool_use',
                  'name': 'extract',
                  'input': {'name': 'Jo'},
                },
              ],
            }),
            200,
          ));
      final adapter =
          AnthropicAdapter(apiKey: 'key', model: 'm', client: client);
      await expectLater(
        adapter.complete(_request()),
        throwsA(isA<AdapterException>()
            .having((e) => e.body, 'body', contains('max_tokens'))),
      );
    });

    test('rejects requests with no non-system messages', () async {
      final adapter = AnthropicAdapter(
          apiKey: 'key',
          model: 'm',
          client: MockClient((r) async => http.Response('', 200)));
      await expectLater(
        adapter.complete(LlmRequest(
          messages: const [Message.system('only system')],
          toolName: 'extract',
          toolDescription: 'd',
          jsonSchema: Schema.object({'a': Schema.string()}).toJsonSchema(),
        )),
        throwsArgumentError,
      );
    });
  });

  group('OpenAIAdapter response variants', () {
    test('accepts tool arguments that are already a JSON object', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'function': {
                          'name': 'extract',
                          'arguments': {'name': 'John'},
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          ));
      final adapter = OpenAIAdapter(apiKey: 'key', model: 'm', client: client);
      final response = await adapter.complete(_request());
      expect(response.toolArguments, {'name': 'John'});
    });

    test('joins content-part arrays into text', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': [
                      {'type': 'text', 'text': '{"name":'},
                      {'type': 'text', 'text': ' "John"}'},
                    ],
                  },
                },
              ],
            }),
            200,
          ));
      final adapter = OpenAIAdapter(apiKey: 'key', model: 'm', client: client);
      final response = await adapter.complete(_request());
      expect(response.text, '{"name": "John"}');
    });

    test('wraps non-JSON 200 bodies in AdapterException', () async {
      final client = MockClient(
          (request) async => http.Response('<html>gateway error</html>', 200));
      final adapter = OpenAIAdapter(apiKey: 'key', model: 'm', client: client);
      await expectLater(
        adapter.complete(_request()),
        throwsA(isA<AdapterException>()
            .having((e) => e.body, 'body', contains('not JSON'))),
      );
    });
  });
}
