import 'dart:io';

import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/daemon/client.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/daemon/server.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/fake_backend.dart';
import 'support/requests.dart';

void main() {
  test('get grammar validates targets and documents units', () {
    final parser = CliParser();
    expect(parser.parse(['get', 'text', '@e1']).params, {
      'action': 'text',
      'ref': '@e1',
    });
    expect(parser.parse(['get', 'count', '--text', 'Hello']).params, {
      'action': 'count',
      'text': 'Hello',
    });
    expect(parser.usage, contains('Flutter logical pixels'));
    for (final args in [
      ['get'],
      ['get', 'text'],
      ['get', 'count', '@e1'],
      ['get', 'box', '@e1', '--key', 'a'],
      ['get', 'text', '@e1', 'extra'],
      ['get', 'unknown'],
    ]) {
      expect(() => parser.parse(args), throwsA(isA<AgentError>()));
    }
  });
  late FakeBackend backend;
  late SessionManager manager;
  setUp(() async {
    backend = FakeBackend()..elements = [ElementInfo(key: 'item')];
    manager = SessionManager(() => backend, coreCommands());
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1/'}),
    );
  });
  tearDown(() => manager.dispose());
  test(
    'IPC preserves nulls, unknown candidates, ambiguity and stale errors',
    () async {
      final directory = await Directory('/tmp').createTemp('mra-get-ipc-');
      final runtime = await RuntimeDirectory.prepare(
        directory: '${directory.path}/r',
      );
      final server = DaemonServer(runtime, manager);
      final serving = server.run();
      try {
        while (!File(runtime.metadata).existsSync()) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final client = DaemonClient(runtime);
        Future<Result> send(String action, Json target) =>
            client.send(request('get', params: {'action': action, ...target}));
        final snapshot = await client.send(request('snapshot'));
        final ref = (snapshot.data!['elements'] as List).single['ref'];
        expect((await send('text', {'ref': ref})).data, {'text': null});
        expect((await send('box', {'ref': ref})).data!['bounds'], isNull);
        backend.elements.add(ElementInfo(key: 'other', text: 'unknown'));
        expect((await send('count', {'text': 'unknown'})).data!['count'], 1);
        expect(
          (await send('text', {'text': 'unknown'})).error!.code,
          'UNRESOLVABLE_TARGET',
        );
        backend.elements.add(ElementInfo(key: 'item'));
        expect(
          (await send('text', {'ref': ref})).error!.code,
          'AMBIGUOUS_TARGET',
        );
        backend.elements = [];
        expect((await send('box', {'ref': ref})).error!.code, 'STALE_REF');
      } finally {
        await server.close();
        await serving;
        await directory.delete(recursive: true);
      }
    },
  );
  Future<Result> get(String action, Json target) =>
      manager.handle(request('get', params: {'action': action, ...target}));
  Future<String> ref() async =>
      ((await manager.handle(request('snapshot'))).data!['elements'] as List)
              .single['ref']
          as String;

  test(
    'null properties remain null and all reads preserve the same ref',
    () async {
      final target = await ref();
      expect((await get('text', {'ref': target})).data, {'text': null});
      expect((await get('box', {'ref': target})).data, {
        'bounds': null,
        'unit': 'flutter_logical_pixels',
      });
      expect((await get('count', {'key': 'item'})).data, {
        'count': 1,
        'selector': {'key': 'item'},
      });
      expect(
        (await manager.handle(request('tap', params: {'ref': target})))
            .exitCode,
        0,
      );
    },
  );
  test(
    'observed values include empty text and real zero coordinates',
    () async {
      final bounds = {'x': 0, 'y': 0, 'width': 20, 'height': 30};
      backend.elements = [ElementInfo(key: 'item', text: '', bounds: bounds)];
      expect((await get('text', {'key': 'item'})).data, {'text': ''});
      expect((await get('box', {'key': 'item'})).data, {
        'bounds': bounds,
        'unit': 'flutter_logical_pixels',
      });
    },
  );
  for (final action in ['text', 'box']) {
    test(
      '$action distinguishes missing, ambiguous and stale targets',
      () async {
        final target = await ref();
        expect(
          (await get(action, {'key': 'missing'})).error!.code,
          'TARGET_NOT_FOUND',
        );
        backend.elements.add(ElementInfo(key: 'item'));
        expect(
          (await get(action, {'ref': target})).error!.code,
          'AMBIGUOUS_TARGET',
        );
        backend.elements = [ElementInfo(key: 'item', text: 'changed')];
        expect((await get(action, {'ref': target})).error!.code, 'STALE_REF');
        backend.elements = [];
        expect((await get(action, {'ref': target})).error!.code, 'STALE_REF');
        expect(
          (await get(action, {'ref': '@e99999'})).error!.code,
          'STALE_REF',
        );
      },
    );
  }
  test(
    'count includes all exact discovery candidates, including unknown text',
    () async {
      backend.elements = [
        ElementInfo(type: 'Text', text: 'Hello', textMatchable: true),
        ElementInfo(type: 'CustomText', text: 'Hello'),
        ElementInfo(type: 'Text', text: 'hello', textMatchable: true),
      ];
      for (final entry in {'missing': 0, 'hello': 1, 'Hello': 2}.entries) {
        expect(
          (await get('count', {'text': entry.key})).data!['count'],
          entry.value,
        );
      }
      expect(
        (await get('text', {'text': 'Hello'})).error!.code,
        'AMBIGUOUS_TARGET',
      );
      backend.elements.removeAt(0);
      expect((await get('count', {'text': 'Hello'})).data!['count'], 1);
      expect(
        (await get('text', {'text': 'Hello'})).error!.code,
        'UNRESOLVABLE_TARGET',
      );
      expect(
        (await get('count', {'identifier': 'item'})).error!.code,
        'UNSUPPORTED_CAPABILITY',
      );
    },
  );
  test('malformed IPC rejects refs for count, including null refs', () async {
    for (final target in <Json>[
      {'ref': '@e1'},
      {'ref': null, 'key': 'item'},
      {},
      {'key': 'item', 'type': 'Text'},
      {'key': false},
      {'key': 'item', 'extra': 1},
    ]) {
      expect((await get('count', target)).error!.code, 'INVALID_ARGUMENT');
    }
  });
}
