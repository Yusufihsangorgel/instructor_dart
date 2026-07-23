/// A single problem found while validating a value against a [Schema].
final class SchemaViolation {
  const SchemaViolation(this.path, this.message);

  /// JSONPath-style location of the problem, e.g. `$.address.street`.
  final String path;

  /// Human-readable description of what is wrong at [path].
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Declarative description of the shape of data expected from a model.
///
/// A schema does two jobs with one definition: it renders to JSON Schema
/// (sent to the provider as a tool/function signature) and it validates the
/// decoded response before it reaches your code.
sealed class Schema {
  const Schema({this.description, this.isOptional = false});

  /// Optional description forwarded into the JSON Schema. Models read
  /// these when deciding what to put in each field.
  final String? description;

  /// Whether this schema may be omitted when used as an object property.
  /// Optional properties are left out of the object's `required` list.
  final bool isOptional;

  /// Renders this schema as a JSON Schema fragment.
  Map<String, Object?> toJsonSchema();

  /// Validates [value]. Returns an empty list when the value conforms.
  List<SchemaViolation> validate(Object? value) {
    final out = <SchemaViolation>[];
    collectViolations(value, r'$', out);
    return out;
  }

  /// Implementation hook for [validate]; appends problems to [out].
  /// Call [validate] instead; this is public only so that schema types can
  /// recurse into each other.
  void collectViolations(Object? value, String path, List<SchemaViolation> out);

  /// Returns [value] coerced to the Dart type this schema guarantees.
  ///
  /// Called only on values that have already passed [validate], so it may
  /// assume the value conforms. The base implementation returns [value]
  /// unchanged; numeric and container schemas override it so that an
  /// `integer` field is always an `int` and a `number` field is always a
  /// `double`, matching JSON Schema semantics on both the Dart VM and the web.
  Object? normalize(Object? value) => value;

  Map<String, Object?> _base(String type) => {
        'type': type,
        if (description != null) 'description': description,
      };

  /// An object with named [properties]. Properties are required unless
  /// marked with `optional()`.
  static ObjectSchema object(
    Map<String, Schema> properties, {
    String? description,
    bool allowAdditionalProperties = false,
  }) =>
      ObjectSchema._(
        properties,
        description: description,
        allowAdditionalProperties: allowAdditionalProperties,
      );

  /// A string, optionally constrained by length or a regular expression.
  ///
  /// Throws [FormatException] immediately when [pattern] is not a valid
  /// regular expression, rather than at first validation.
  static StringSchema string({
    String? description,
    int? minLength,
    int? maxLength,
    String? pattern,
  }) {
    if (pattern != null) RegExp(pattern);
    return StringSchema._(
      description: description,
      minLength: minLength,
      maxLength: maxLength,
      pattern: pattern,
    );
  }

  /// An integer, optionally bounded by [min] and [max] (inclusive).
  static IntegerSchema integer({String? description, int? min, int? max}) =>
      IntegerSchema._(description: description, min: min, max: max);

  /// A number (integer or double), optionally bounded (inclusive).
  static NumberSchema number({String? description, num? min, num? max}) =>
      NumberSchema._(description: description, min: min, max: max);

  /// A boolean.
  static BooleanSchema boolean({String? description}) =>
      BooleanSchema._(description: description);

  /// A string restricted to one of [values].
  ///
  /// [values] must not be empty and is copied, so later changes to the
  /// original list do not affect the schema.
  static EnumSchema enumeration(List<String> values, {String? description}) {
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }
    return EnumSchema._(List.unmodifiable(values), description: description);
  }

  /// A list whose elements each match [items].
  static ListSchema list(
    Schema items, {
    String? description,
    int? minItems,
    int? maxItems,
  }) =>
      ListSchema._(
        items,
        description: description,
        minItems: minItems,
        maxItems: maxItems,
      );
}

String _typeName(Object? value) => switch (value) {
      null => 'null',
      String() => 'a string',
      bool() => 'a boolean',
      int() => 'an integer',
      double() => 'a number',
      List() => 'a list',
      Map() => 'an object',
      _ => value.runtimeType.toString(),
    };

/// Schema for string values. See [Schema.string].
final class StringSchema extends Schema {
  const StringSchema._({
    super.description,
    super.isOptional,
    this.minLength,
    this.maxLength,
    this.pattern,
  });

  final int? minLength;
  final int? maxLength;

  /// Regular expression (JSON Schema `pattern`) the value must match.
  final String? pattern;

  /// A copy of this schema that may be omitted as an object property.
  StringSchema optional() => StringSchema._(
        description: description,
        isOptional: true,
        minLength: minLength,
        maxLength: maxLength,
        pattern: pattern,
      );

  @override
  Map<String, Object?> toJsonSchema() => {
        ..._base('string'),
        if (minLength != null) 'minLength': minLength,
        if (maxLength != null) 'maxLength': maxLength,
        if (pattern != null) 'pattern': pattern,
      };

  @override
  void collectViolations(
      Object? value, String path, List<SchemaViolation> out) {
    if (value is! String) {
      out.add(
          SchemaViolation(path, 'expected a string, got ${_typeName(value)}'));
      return;
    }
    if (minLength != null && value.length < minLength!) {
      out.add(SchemaViolation(path,
          'expected at least $minLength characters, got ${value.length}'));
    }
    if (maxLength != null && value.length > maxLength!) {
      out.add(SchemaViolation(
          path, 'expected at most $maxLength characters, got ${value.length}'));
    }
    if (pattern != null && !RegExp(pattern!).hasMatch(value)) {
      out.add(SchemaViolation(path, 'does not match pattern $pattern'));
    }
  }
}

/// Schema for integer values. See [Schema.integer].
///
/// Follows the JSON Schema definition of `integer`: numbers with a zero
/// fractional part, such as `25.0`, are accepted. This also keeps
/// validation consistent between the Dart VM (where `jsonDecode('25.0')`
/// yields a `double`) and the web (where it yields an `int`).
final class IntegerSchema extends Schema {
  const IntegerSchema._(
      {super.description, super.isOptional, this.min, this.max});

  final int? min;
  final int? max;

  /// A copy of this schema that may be omitted as an object property.
  IntegerSchema optional() => IntegerSchema._(
      description: description, isOptional: true, min: min, max: max);

  @override
  Map<String, Object?> toJsonSchema() => {
        ..._base('integer'),
        if (min != null) 'minimum': min,
        if (max != null) 'maximum': max,
      };

  @override
  void collectViolations(
      Object? value, String path, List<SchemaViolation> out) {
    final isIntegral = value is int ||
        (value is double &&
            value.isFinite &&
            value.truncateToDouble() == value);
    if (!isIntegral) {
      out.add(SchemaViolation(
          path, 'expected an integer, got ${_typeName(value)}'));
      return;
    }
    final number = value as num;
    if (min != null && number < min!) {
      out.add(SchemaViolation(path, 'expected >= $min, got $value'));
    }
    if (max != null && number > max!) {
      out.add(SchemaViolation(path, 'expected <= $max, got $value'));
    }
  }

  @override
  Object? normalize(Object? value) {
    // `jsonDecode('25.0')` yields a `double` on the VM but an `int` on the
    // web; collapse integral doubles to `int` so an `integer` field is always
    // an `int`. Values outside the safe integer range are left alone rather
    // than converted lossily.
    const maxSafeInteger = 9007199254740992.0; // 2^53
    if (value is double &&
        value.isFinite &&
        value.truncateToDouble() == value &&
        value.abs() <= maxSafeInteger) {
      return value.toInt();
    }
    return value;
  }
}

/// Schema for numeric values (integer or double). See [Schema.number].
final class NumberSchema extends Schema {
  const NumberSchema._(
      {super.description, super.isOptional, this.min, this.max});

  final num? min;
  final num? max;

  /// A copy of this schema that may be omitted as an object property.
  NumberSchema optional() => NumberSchema._(
      description: description, isOptional: true, min: min, max: max);

  @override
  Map<String, Object?> toJsonSchema() => {
        ..._base('number'),
        if (min != null) 'minimum': min,
        if (max != null) 'maximum': max,
      };

  @override
  void collectViolations(
      Object? value, String path, List<SchemaViolation> out) {
    if (value is! num) {
      out.add(
          SchemaViolation(path, 'expected a number, got ${_typeName(value)}'));
      return;
    }
    if (min != null && value < min!) {
      out.add(SchemaViolation(path, 'expected >= $min, got $value'));
    }
    if (max != null && value > max!) {
      out.add(SchemaViolation(path, 'expected <= $max, got $value'));
    }
  }

  @override
  Object? normalize(Object? value) => value is num ? value.toDouble() : value;
}

/// Schema for boolean values. See [Schema.boolean].
final class BooleanSchema extends Schema {
  const BooleanSchema._({super.description, super.isOptional});

  /// A copy of this schema that may be omitted as an object property.
  BooleanSchema optional() =>
      BooleanSchema._(description: description, isOptional: true);

  @override
  Map<String, Object?> toJsonSchema() => _base('boolean');

  @override
  void collectViolations(
      Object? value, String path, List<SchemaViolation> out) {
    if (value is! bool) {
      out.add(
          SchemaViolation(path, 'expected a boolean, got ${_typeName(value)}'));
    }
  }
}

/// Schema for a string restricted to a fixed set of values.
/// See [Schema.enumeration].
final class EnumSchema extends Schema {
  const EnumSchema._(this.values, {super.description, super.isOptional});

  final List<String> values;

  /// A copy of this schema that may be omitted as an object property.
  EnumSchema optional() =>
      EnumSchema._(values, description: description, isOptional: true);

  @override
  Map<String, Object?> toJsonSchema() => {
        ..._base('string'),
        'enum': values,
      };

  @override
  void collectViolations(
      Object? value, String path, List<SchemaViolation> out) {
    if (value is! String || !values.contains(value)) {
      out.add(SchemaViolation(
          path, 'expected one of ${values.join(', ')}, got $value'));
    }
  }
}

/// Schema for lists. See [Schema.list].
final class ListSchema extends Schema {
  const ListSchema._(
    this.items, {
    super.description,
    super.isOptional,
    this.minItems,
    this.maxItems,
  });

  final Schema items;
  final int? minItems;
  final int? maxItems;

  /// A copy of this schema that may be omitted as an object property.
  ListSchema optional() => ListSchema._(
        items,
        description: description,
        isOptional: true,
        minItems: minItems,
        maxItems: maxItems,
      );

  @override
  Map<String, Object?> toJsonSchema() => {
        ..._base('array'),
        'items': items.toJsonSchema(),
        if (minItems != null) 'minItems': minItems,
        if (maxItems != null) 'maxItems': maxItems,
      };

  @override
  void collectViolations(
      Object? value, String path, List<SchemaViolation> out) {
    if (value is! List) {
      out.add(
          SchemaViolation(path, 'expected a list, got ${_typeName(value)}'));
      return;
    }
    if (minItems != null && value.length < minItems!) {
      out.add(SchemaViolation(
          path, 'expected at least $minItems items, got ${value.length}'));
    }
    if (maxItems != null && value.length > maxItems!) {
      out.add(SchemaViolation(
          path, 'expected at most $maxItems items, got ${value.length}'));
    }
    for (var i = 0; i < value.length; i++) {
      items.collectViolations(value[i], '$path[$i]', out);
    }
  }

  @override
  Object? normalize(Object? value) =>
      value is List ? [for (final item in value) items.normalize(item)] : value;
}

/// Schema for objects with named properties. See [Schema.object].
final class ObjectSchema extends Schema {
  const ObjectSchema._(
    this.properties, {
    super.description,
    super.isOptional,
    this.allowAdditionalProperties = false,
  });

  final Map<String, Schema> properties;

  /// Whether keys not listed in [properties] are tolerated. Defaults to
  /// false: unexpected keys are reported as violations, matching the
  /// `additionalProperties: false` emitted in the JSON Schema.
  final bool allowAdditionalProperties;

  /// A copy of this schema that may be omitted as an object property.
  ObjectSchema optional() => ObjectSchema._(
        properties,
        description: description,
        isOptional: true,
        allowAdditionalProperties: allowAdditionalProperties,
      );

  @override
  Map<String, Object?> toJsonSchema() {
    final required = [
      for (final entry in properties.entries)
        if (!entry.value.isOptional) entry.key,
    ];
    return {
      ..._base('object'),
      'properties': {
        for (final entry in properties.entries)
          entry.key: entry.value.toJsonSchema(),
      },
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': allowAdditionalProperties,
    };
  }

  @override
  void collectViolations(
      Object? value, String path, List<SchemaViolation> out) {
    if (value is! Map) {
      out.add(
          SchemaViolation(path, 'expected an object, got ${_typeName(value)}'));
      return;
    }
    for (final entry in properties.entries) {
      final present = value.containsKey(entry.key);
      if (!present) {
        if (!entry.value.isOptional) {
          out.add(SchemaViolation(
              '$path.${entry.key}', 'required property is missing'));
        }
        continue;
      }
      final propertyValue = value[entry.key];
      // Forced tool calling on OpenAI, Anthropic and Gemini fills in every
      // declared parameter and represents "no value" as an explicit `null`
      // rather than omitting the key. Treat that the same as an absent
      // optional property instead of failing it against the leaf schema.
      if (propertyValue == null && entry.value.isOptional) continue;
      entry.value.collectViolations(propertyValue, '$path.${entry.key}', out);
    }
    if (!allowAdditionalProperties) {
      for (final key in value.keys) {
        if (key is! String || !properties.containsKey(key)) {
          out.add(SchemaViolation('$path.$key', 'unexpected property'));
        }
      }
    }
  }

  @override
  Object? normalize(Object? value) {
    if (value is! Map) return value;
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String:
            properties[entry.key]?.normalize(entry.value) ?? entry.value,
    };
  }
}
