import 'dart:convert';

import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/fake_backend.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/cli/renderer.dart';
import 'package:marionette_agent/src/commands/core_commands.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;

void main() {
  late FakeBackend backend;
  late SessionManager manager;
  setUp(() async {
    backend = FakeBackend()
      ..elements = [
        ElementInfo(
          type: 'Button',
          key: 'first',
          text: 'Same',
          textMatchable: true,
        ),
        ElementInfo(
          type: 'Button',
          key: 'second',
          text: 'Same',
          textMatchable: true,
        ),
        ElementInfo(type: 'Unknown', text: 'Display only', identifier: 'label'),
        ElementInfo(type: 'Unknown'),
      ];
    manager = SessionManager(() => backend, coreCommands());
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
  });
  tearDown(() => manager.dispose());

  Future<Result> snapshot(Json params, {int? maximum, bool json = false}) =>
      manager.handle(
        Request(
          requestId: 'filter',
          session: 'a',
          command: 'snapshot',
          params: params,
          deadline: DateTime.now().add(const Duration(seconds: 2)),
          maxOutput: maximum,
          outputJson: json,
        ),
      );
  Future<Result> tap(String ref) =>
      manager.handle(request('tap', params: {'ref': ref}));

  test('all filters accept zero, one and multiple observed matches', () async {
    for (final entry in <String, String>{
      'key': 'first',
      'identifier': 'label',
      'text': 'Display only',
      'type': 'Button',
    }.entries) {
      final result = await snapshot({entry.key: entry.value});
      expect(result.exitCode, 0);
      expect(result.data!['filter'], {
        'kind': entry.key,
        'value': entry.value,
        'matchedCount': entry.key == 'type' ? 2 : 1,
        'totalCount': 4,
      });
    }
    final multiple = await snapshot({'text': 'Same'});
    expect(multiple.exitCode, 0);
    expect(multiple.data!['elements'], hasLength(2));
    final empty = await snapshot({'key': 'absent'});
    expect(empty.exitCode, 0);
    expect(empty.data!['elements'], isEmpty);
    expect((empty.data!['filter'] as Map)['matchedCount'], 0);
    final full = await snapshot({});
    expect(full.data!.keys, unorderedEquals(['generation', 'elements']));
    expect(full.data!['elements'], hasLength(4));
  });

  test(
    'display-only text and unsupported identifier preserve hidden collisions',
    () async {
      for (final params in [
        {'text': 'Display only'},
        {'identifier': 'label'},
      ]) {
        final result = await snapshot(params);
        final row = (result.data!['elements'] as List).single as Map;
        expect(row['ref'], isNull);
        expect(row['reason'], 'no_unique_supported_selector');
      }
      expect(backend.selectors, isNot(contains(SelectorKind.identifier)));
    },
  );

  test(
    'full observation numbering and only returned refs remain actionable',
    () async {
      final full = await snapshot({});
      final old =
          ((full.data!['elements'] as List).first as Map)['ref'] as String;
      final filtered = await snapshot({'key': 'second'});
      final current =
          ((filtered.data!['elements'] as List).single as Map)['ref'] as String;
      expect(current, '@e4');
      expect((await tap(old)).error!.code, 'STALE_REF');
      expect((await tap('@e3')).error!.code, 'STALE_REF');
      expect((await tap(current)).exitCode, 0);
      expect(backend.calls.where((call) => call == 'tap'), hasLength(1));
      final next = await snapshot({'key': 'first'});
      final nextRef =
          ((next.data!['elements'] as List).single as Map)['ref'] as String;
      final empty = await snapshot({'key': 'absent'});
      expect(
        empty.data!['generation'],
        greaterThan(next.data!['generation'] as int),
      );
      expect((await tap(nextRef)).error!.code, 'STALE_REF');
    },
  );

  test(
    'filter precedes output limits in both renderings and omitted refs expire',
    () async {
      for (final json in [false, true]) {
        final result = await snapshot(
          {'type': 'Button'},
          maximum: 1,
          json: json,
        );
        expect(result.data!['elements'], isEmpty);
        expect(result.data!['truncated'], true);
        expect(result.data!['originalCount'], 2);
        expect(result.data!['omittedCount'], 2);
        expect((result.data!['filter'] as Map)['totalCount'], 4);
        final output = render(result, json: json, contentBoundaries: true);
        if (json) {
          expect(jsonDecode(output)['data']['filter']['matchedCount'], 2);
        } else {
          expect(
            output,
            contains('Filter: type="Button"; matchedCount: 2; totalCount: 4'),
          );
          expect(
            output,
            contains('Truncated: true; originalCount: 2; omittedCount: 2'),
          );
        }
      }
      expect((await tap('@e3')).error!.code, 'STALE_REF');
      final empty = await snapshot({'key': 'absent'}, maximum: 1);
      expect(empty.data!['truncated'], false);
      expect(empty.data!['originalCount'], 0);
      final retained = await snapshot({'key': 'second'}, maximum: 10000);
      expect(retained.data!['truncated'], false);
      final ref =
          ((retained.data!['elements'] as List).single as Map)['ref'] as String;
      expect((await tap(ref)).exitCode, 0);
    },
  );

  test(
    'invalid filters fail before observation and preserve valid refs',
    () async {
      final result = await snapshot({'key': 'first'});
      final ref =
          ((result.data!['elements'] as List).single as Map)['ref'] as String;
      final calls = backend.calls.length;
      for (final params in <Json>[
        {'key': ''},
        {'text': 1},
        {'ref': '@e1'},
        {'key': 'first', 'type': 'Button'},
        {'other': 'x'},
      ]) {
        expect((await snapshot(params)).error!.code, 'INVALID_ARGUMENT');
      }
      expect(backend.calls.length, calls);
      expect((await tap(ref)).exitCode, 0);
    },
  );

  test('CLI grammar permits one exact filter and common options', () {
    final parser = CliParser();
    for (final kind in SelectorKind.values) {
      expect(
        parser.parse([
          'snapshot',
          '--${kind.name}',
          'two words',
          '--json',
          '--max-output',
          '100',
        ]).params,
        {kind.name: 'two words'},
      );
    }
    for (final args in [
      ['snapshot', '--key', ''],
      ['snapshot', '--key'],
      ['snapshot', '--key', 'a', '--key', 'b'],
      ['snapshot', '--key', 'a', '--text', 'b'],
      ['snapshot', '@e1'],
      ['snapshot', '--ref', '@e1'],
    ]) {
      expect(() => parser.parse(args), throwsA(isA<AgentError>()));
    }
    expect(parser.parse(['snapshot']).params, isEmpty);
  });
}
