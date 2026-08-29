import 'package:stream_struct/stream_struct.dart';
import 'package:test/test.dart';

import '../example/with_stream_struct.dart';

void main() {
  const silent = _ignore;

  group('stream then extract', () {
    test('valid chunks fill in, then extract succeeds on the last frame',
        () async {
      final frames = <String>[];
      final last = await fill(validChunks, log: frames.add);
      expect(last, isNotNull);
      expect(
        frames,
        [
          '  Foc | ? | (none yet)',
          '  Focaccia | 2 min | (none yet)',
          '  Focaccia | 20 min | flour',
          '  Focaccia | 20 min | flour, water, olive oil',
        ],
      );
      expect(recipeSchema.validate(last!), isEmpty);

      final recipe = await play(
        label: 'matches',
        chunks: validChunks,
        log: silent,
      );
      expect(recipe, isNotNull);
      expect(recipe!.title, 'Focaccia');
      expect(recipe.prepMinutes, 20);
      expect(recipe.ingredients, ['flour', 'water', 'olive oil']);
    });

    test('invalid last frame is rejected and repaired', () async {
      final frames = <String>[];
      final last = await fill(invalidChunks, log: frames.add);
      expect(last, isNotNull);
      expect(
        frames,
        [
          '  Burnt toast | 99 min | (none yet)',
          '  Burnt toast | 999 min | bread',
        ],
      );

      final violations = recipeSchema.validate(last!);
      expect(violations, hasLength(1));
      expect(violations.single.path, r'$.prep_min');
      expect(violations.single.message, 'expected <= 180, got 999');

      final lines = <String>[];
      final recipe = await play(
        label: 'fails',
        chunks: invalidChunks,
        repair: repaired,
        log: lines.add,
      );
      expect(recipe, isNotNull);
      expect(recipe!.title, 'Focaccia');
      expect(recipe.prepMinutes, 20);
      expect(
        lines.where((l) => l.contains('rejected')),
        [
          '  attempt 1 rejected: \$.prep_min: expected <= 180, got 999',
        ],
      );
      expect(
        lines.where((l) => l.contains('the model was called')),
        ['     the model was called 2 time(s)'],
      );
    });

    test('a mid-stream frame is not a repair opportunity', () async {
      // The first valid chunk is `{"title": "Foc`. Validating that
      // reports missing required fields while the model is still typing.
      Map<String, dynamic>? first;
      await for (final partial in streamPartialJsonFrom(
        Stream.fromIterable(validChunks),
        openAiToolDelta(),
      )) {
        if (partial is Map<String, dynamic>) {
          first = partial;
          break;
        }
      }
      expect(first, isNotNull);
      final json = Map<String, Object?>.from(first!);
      expect(
        recipeSchema.validate(json).map((v) => v.path),
        containsAll([r'$.prep_min', r'$.ingredients']),
      );
    });
  });
}

void _ignore(String _) {}
