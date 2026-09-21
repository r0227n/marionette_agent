import 'dart:convert';
import 'dart:typed_data';

import 'package:marionette_agent/src/cli/observation_diff.dart';
import 'package:test/test.dart';

void main() {
  test(
    'snapshot diff counts duplicate nested rows regardless of map order',
    () async {
      final result = await compareObservation(
        {'action': 'snapshot'},
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'elements': [
                {
                  'ref': '@e1',
                  'bounds': {'x': 1, 'y': 2},
                  'text': 'same',
                },
                {'text': 'gone'},
                {'text': 'gone'},
              ],
            }),
          ),
        ),
        {
          'elements': [
            {'text': 'new'},
            {
              'text': 'same',
              'bounds': {'y': 2.0, 'x': 1.0},
              'ref': '@e20',
            },
            {'text': 'gone'},
            {'text': 'new'},
          ],
        },
        DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(result, {
        'changed': true,
        'added': [
          {'text': 'new'},
          {'text': 'new'},
        ],
        'removed': [
          {'text': 'gone'},
        ],
      });
    },
  );

  test(
    'large reversed observations compare within the caller deadline',
    () async {
      final rows = List.generate(
        12000,
        (i) => {
          'key': 'key-$i',
          'bounds': {'x': i, 'y': 0},
        },
      );
      final baseline = Uint8List.fromList(
        utf8.encode(jsonEncode({'elements': rows})),
      );
      final result = await compareObservation(
        {'action': 'snapshot'},
        baseline,
        {'elements': rows.reversed.toList()},
        DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(result, {'changed': false, 'added': [], 'removed': []});
    },
  );
}
