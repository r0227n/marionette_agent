import 'package:test/test.dart';

import '../integration_test/record_smoke.dart' show runWithCleanup;

void main() {
  test(
    'cleanup failure preserves original error and runs remaining cleanup',
    () async {
      final original = StateError('operation failed');
      final stack = StackTrace.current;
      final stages = <String>[];
      try {
        await runWithCleanup(
          () async => Error.throwWithStackTrace(original, stack),
          [
            () async {
              stages.add('close');
              throw StateError('close failed');
            },
            () async {
              stages.add('evidence');
              throw StateError('write failed');
            },
            () async {
              stages.add('delete');
            },
          ],
        );
        fail('Expected failure');
      } catch (error, trace) {
        expect(error, same(original));
        expect(trace.toString(), stack.toString());
      }
      expect(stages, ['close', 'evidence', 'delete']);
    },
  );
  test('cleanup failure fails an otherwise successful smoke run', () async {
    final error = StateError('close failed');
    var saved = false;
    await expectLater(
      runWithCleanup(() async {}, [
        () async => throw error,
        () async {
          saved = true;
        },
      ]),
      throwsA(same(error)),
    );
    expect(saved, isTrue);
  });
}
