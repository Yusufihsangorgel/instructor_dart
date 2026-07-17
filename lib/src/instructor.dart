import 'dart:convert';

import 'adapter.dart';
import 'message.dart';
import 'schema.dart';

/// One failed attempt inside `extract`/`extractRaw`.
final class ExtractionAttempt {
  const ExtractionAttempt({
    required this.number,
    required this.violations,
    required this.rawResponse,
  });

  /// 1-based attempt number.
  final int number;

  /// Why this attempt was rejected.
  final List<SchemaViolation> violations;

  /// What the model returned, for debugging and for the repair prompt.
  final String rawResponse;
}

/// Thrown when the model failed to produce schema-conforming data within
/// the configured number of attempts. Carries every attempt so failures are
/// debuggable instead of opaque.
final class ExtractionException implements Exception {
  const ExtractionException(this.attempts);

  final List<ExtractionAttempt> attempts;

  @override
  String toString() {
    final last = attempts.isEmpty ? '' : attempts.last.violations.join('; ');
    return 'ExtractionException: no valid response after '
        '${attempts.length} attempt(s). Last problems: $last';
  }
}

/// Extracts typed, schema-validated data from an LLM.
///
/// The model is asked to call a tool whose parameters are your schema. The
/// response is validated locally; if it does not conform, the violations are
/// sent back to the model and it gets another try, up to `maxRetries` times.
final class Instructor {
  Instructor({required LlmAdapter adapter}) : _adapter = adapter;

  final LlmAdapter _adapter;

  /// Extracts a [T] from the model.
  ///
  /// [fromJson] runs only after the response has passed schema validation,
  /// so it can assume every required field is present and correctly typed.
  Future<T> extract<T>({
    required List<Message> messages,
    required ObjectSchema schema,
    required T Function(Map<String, Object?> json) fromJson,
    String toolName = 'extract',
    String? toolDescription,
    int maxRetries = 2,
    void Function(ExtractionAttempt attempt)? onRetry,
  }) async {
    final raw = await extractRaw(
      messages: messages,
      schema: schema,
      toolName: toolName,
      toolDescription: toolDescription,
      maxRetries: maxRetries,
      onRetry: onRetry,
    );
    return fromJson(raw);
  }

  /// Like [extract], but returns the validated JSON object as-is.
  ///
  /// Integral doubles (`25.0`) in the response are coerced to `int` before
  /// validation, so casts like `json['age'] as int` behave the same on the
  /// Dart VM and the web.
  ///
  /// Exceptions thrown by the adapter, such as [AdapterException], propagate
  /// immediately; only schema violations are retried.
  Future<Map<String, Object?>> extractRaw({
    required List<Message> messages,
    required ObjectSchema schema,
    String toolName = 'extract',
    String? toolDescription,
    int maxRetries = 2,
    void Function(ExtractionAttempt attempt)? onRetry,
  }) async {
    if (maxRetries < 0) {
      throw ArgumentError.value(maxRetries, 'maxRetries', 'must be >= 0');
    }
    final transcript = List<Message>.of(messages);
    final attempts = <ExtractionAttempt>[];
    final jsonSchema = schema.toJsonSchema();
    final totalAttempts = maxRetries + 1;

    for (var attempt = 1; attempt <= totalAttempts; attempt++) {
      final response = await _adapter.complete(LlmRequest(
        messages: List.unmodifiable(transcript),
        toolName: toolName,
        toolDescription: toolDescription ??
            'Record the extracted data as structured fields.',
        jsonSchema: jsonSchema,
      ));

      final violations = <SchemaViolation>[];
      Map<String, Object?>? candidate;
      if (response.toolArguments != null) {
        candidate = response.toolArguments;
      } else if (response.text != null) {
        candidate = _decodeJsonObject(response.text!);
        if (candidate == null) {
          violations.add(
              const SchemaViolation(r'$', 'response is not a JSON object'));
        }
      } else {
        violations.add(const SchemaViolation(
            r'$', 'model returned neither a tool call nor text'));
      }
      if (candidate != null) {
        candidate = _coerceIntegralDoubles(candidate) as Map<String, Object?>;
        violations.addAll(schema.validate(candidate));
      }
      if (violations.isEmpty) {
        return candidate!;
      }

      final raw = response.text ??
          (response.toolArguments == null
              ? ''
              : jsonEncode(response.toolArguments));
      final record = ExtractionAttempt(
        number: attempt,
        violations: violations,
        rawResponse: raw,
      );
      attempts.add(record);
      if (attempt == totalAttempts) break;

      onRetry?.call(record);
      transcript
        ..add(Message.assistant(raw.isEmpty ? '(no content)' : raw))
        ..add(Message.user(_repairPrompt(violations, toolName)));
    }
    throw ExtractionException(attempts);
  }

  static String _repairPrompt(
      List<SchemaViolation> violations, String toolName) {
    final buffer = StringBuffer(
        'The previous response did not match the required schema.\n')
      ..writeln('Problems:');
    for (final violation in violations) {
      buffer.writeln('- $violation');
    }
    buffer.write(
        'Call the $toolName tool again with data that fixes every problem. '
        'Do not repeat the same mistakes.');
    return buffer.toString();
  }

  /// Best-effort extraction of a JSON object from free-form model text:
  /// direct parse first, then fenced code blocks, then the outermost braces.
  static Map<String, Object?>? _decodeJsonObject(String text) {
    for (final candidate in _jsonCandidates(text)) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded.cast<String, Object?>();
        }
      } on FormatException {
        // Try the next candidate.
      }
    }
    return null;
  }

  /// Recursively converts finite doubles with a zero fractional part into
  /// ints. `jsonDecode` on the VM yields `double` for numbers written as
  /// `25.0` while web compilation yields `int`; coercing removes the
  /// difference. Doubles outside the safe integer range are left alone.
  static Object? _coerceIntegralDoubles(Object? value) {
    const maxSafeInteger = 9007199254740992.0; // 2^53
    if (value is double &&
        value.isFinite &&
        value.truncateToDouble() == value &&
        value.abs() <= maxSafeInteger) {
      return value.toInt();
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key as String: _coerceIntegralDoubles(entry.value),
      };
    }
    if (value is List) {
      return [for (final item in value) _coerceIntegralDoubles(item)];
    }
    return value;
  }

  static Iterable<String> _jsonCandidates(String text) sync* {
    yield text;
    final fence =
        RegExp(r'```(?:json)?\s*(.*?)```', dotAll: true).firstMatch(text);
    if (fence != null) yield fence.group(1)!;
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) yield text.substring(start, end + 1);
  }
}
