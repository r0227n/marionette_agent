import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/cli/artifact_writer.dart';
import 'package:marionette_agent/src/cli/diff_command.dart';
import 'package:marionette_agent/src/cli/renderer.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'session_test.dart' show request;
import 'screenshot_annotation_test.dart' show geometry;

class InteractiveFake extends FakeBackend
    implements InteractionBackend, ClipboardBackend {
  @override
  Set<String> interactions = {
    'dblclick',
    'press',
    'type',
    'check',
    'uncheck',
    'focus',
    'hover',
    'select',
    'scrollintoview',
    'drag',
    'keydown',
    'keyup',
    'keyboard.inserttext',
    'clipboard.read',
    'clipboard.write',
    'clipboard.copy',
    'clipboard.paste',
  };
  Json? lastArguments;
  @override
  Future<void> interact(
    String action, {
    Selector? target,
    Json arguments = const {},
  }) async {
    calls.add(action);
    lastArguments = arguments;
    await hooks[action]?.call();
  }

  @override
  Future<String?> readClipboard() async => 'clipboard';
}

void main() {
  late InteractiveFake backend;
  late SessionManager manager;
  late Directory files;
  setUp(() async {
    files = await Directory.systemTemp.createTemp('mra-parity-test-');
    backend = InteractiveFake()
      ..elements = [
        ElementInfo(
          key: 'a',
          type: 'TextField',
          inputValue: 'value',
          enabled: true,
          checked: false,
          depth: 0,
          interactive: true,
          visible: true,
          label: 'Editable',
          placeholder: 'Type here',
        ),
        ElementInfo(
          key: 'b',
          type: 'Text',
          text: 'Other',
          depth: 1,
          interactive: false,
          visible: true,
        ),
      ];
    manager = SessionManager(() => backend, coreCommands());
    expect(
      (await manager.handle(
        request('connect', params: {'uri': 'http://localhost:1/'}),
      )).exitCode,
      0,
    );
  });
  tearDown(() async {
    await manager.dispose();
    await files.delete(recursive: true);
  });
  Future<Result> cli(List<String> argv) async {
    final invocation = CliParser(environment: {}).parse(argv);
    return manager.handle(
      request(invocation.command, params: invocation.params),
    );
  }

  test(
    'typed values and states distinguish false, empty and unknown',
    () async {
      expect((await cli(['get', 'value', '--key', 'a'])).data, {
        'property': 'value',
        'known': true,
        'value': 'value',
      });
      expect((await cli(['is', 'checked', '--key', 'a'])).data, {
        'property': 'checked',
        'known': true,
        'value': false,
      });
      expect((await cli(['is', 'enabled', '--key', 'b'])).data, {
        'property': 'enabled',
        'known': false,
        'value': null,
      });
      expect(
        render(await cli(['get', 'value', '--key', 'a']), json: false),
        'Value: value',
      );
      expect(backend.calls, isNot(contains('fill')));
    },
  );
  test(
    'filtered snapshot keeps collision safety and hides unpublished refs',
    () async {
      final snapshot = await cli(['snapshot', '--interactive', '--depth', '0']);
      expect((snapshot.data!['elements'] as List).length, 1);
      expect((await cli(['tap', '@e2'])).error!.code, 'STALE_REF');
      expect((await cli(['tap', '@e1'])).exitCode, 0);
    },
  );
  test('depth and interactive never guess missing metadata', () async {
    backend.elements = [ElementInfo(key: 'a')];
    expect(
      (await cli(['snapshot', '--depth', '1'])).error!.code,
      'UNSUPPORTED_CAPABILITY',
    );
    expect(
      (await cli(['snapshot', '--interactive'])).error!.code,
      'UNSUPPORTED_CAPABILITY',
    );
  });
  test('find substring and positional selection still require unique matcher for action', () async {
    expect((await cli(['find', 'label', 'Edit'])).data!['matchedCount'], 1);
    expect(
      (await cli(['find', 'label', 'Edit', '--exact'])).error!.code,
      'TARGET_NOT_FOUND',
    );
    expect(
      (await cli(['find', 'first', '--type', 'TextField', 'type', 'append']))
          .exitCode,
      0,
    );
    expect(backend.lastArguments, {'input': 'append'});
    backend.elements = [
      ElementInfo(type: 'Checkbox', interactive: true),
      ElementInfo(type: 'Checkbox', interactive: true),
    ];
    expect(
      (await cli(['find', 'nth', '1', '--type', 'Checkbox', 'check']))
          .error!
          .code,
      'UNRESOLVABLE_TARGET',
    );
    expect(backend.calls, isNot(contains('check')));
  });
  test(
    'interactions send once and invalidate refs; errors never retry',
    () async {
      await cli(['snapshot']);
      backend.hooks['dblclick'] = () async {
        throw const AgentError('CONNECTION_LOST', 'disconnected');
      };
      final failed = await cli(['dblclick', '@e1']);
      expect(failed.error!.outcome, Outcome.unknown);
      expect(backend.calls.where((call) => call == 'dblclick').length, 1);
      expect(manager.sessions['a']!.observation, isNull);
    },
  );
  test('bad input validates before observations and UI sending', () async {
    final before = backend.calls.length;
    for (final argv in [
      ['press', 'Control+Control+A'],
      ['keydown', 'Control+A'],
      ['select', '--key', 'a'],
      ['snapshot', '--depth', '-1'],
      ['wait', '@e1', '--poll-interval', '1'],
      ['drag', '@e1'],
      [
        'record',
        'start',
        'out.mp4',
        '--platform',
        'ios',
        '--device',
        'invalid',
        '--fps',
        '0',
      ],
    ]) {
      expect(
        () => CliParser().parse(argv),
        throwsA(isA<AgentError>()),
        reason: '$argv',
      );
    }
    expect(backend.calls.length, before);
  });
  test(
    'wait duration and disappearance by saved ref preserve public observation',
    () async {
      await cli(['snapshot']);
      final observation = manager.sessions['a']!.observation;
      expect((await cli(['wait', '0'])).data!['waitedMs'], 0);
      backend.elements.removeAt(0);
      expect((await cli(['wait', '@e1', '--state', 'gone'])).exitCode, 0);
      expect(identical(observation, manager.sessions['a']!.observation), true);
      expect((await cli(['wait', '@e999'])).error!.code, 'STALE_REF');
    },
  );
  test('confirmation text includes actionable id and batch boundaries reach nested data', () {
    final confirmation = Result.failure(
      'a',
      const AgentError(
        'CONFIRMATION_REQUIRED',
        'Confirm',
        details: {'confirmationId': 'abc', 'command': 'tap'},
      ),
    );
    expect(render(confirmation, json: false), contains('Confirmation: abc'));
    final batch = Result.success('a', {
      'completed': 1,
      'results': [
        {
          'command': 'snapshot',
          'data': {
            'elements': [
              {'text': 'untrusted'},
            ],
          },
        },
      ],
    });
    final text = render(batch, json: false, contentBoundaries: true);
    expect(text, contains('BEGIN UNTRUSTED snapshot'));
    expect(text, contains('END UNTRUSTED snapshot'));
  });

  test(
    'clipboard side effects preserve refs but lost delivery is unknown',
    () async {
      await cli(['snapshot']);
      final observation = manager.sessions['a']!.observation;
      expect((await cli(['clipboard', 'write', 'value'])).exitCode, 0);
      expect(identical(observation, manager.sessions['a']!.observation), true);
      backend.hooks['clipboard.write'] = () async {
        throw const AgentError('CONNECTION_LOST', 'lost');
      };
      expect(
        (await cli(['clipboard', 'write', 'value'])).error!.outcome,
        Outcome.unknown,
      );
    },
  );

  test('configuration precedence and aliases reject duplicates without interpreting literals', () async {
    final config = File('${files.path}/config.json')
      ..writeAsStringSync(
        jsonEncode({'session': 'configured', 'timeout': 100, 'json': true}),
      );
    final parser = CliParser(
      environment: {'MARIONETTE_AGENT_SESSION': 'environment'},
    );
    final invocation = parser.parse([
      '--config',
      config.path,
      '--timeout',
      '200',
      'snapshot',
    ]);
    expect(invocation.session, 'environment');
    expect(invocation.timeoutMs, 200);
    expect(invocation.json, true);
    expect(
      parser.parse([
        '--config',
        config.path,
        '--session-name',
        'explicit',
        'snapshot',
      ]).session,
      'explicit',
    );
    expect(
      () => parser.parse(['--session', 'a', '--session-name', 'b', 'snapshot']),
      throwsA(isA<AgentError>()),
    );
    expect(
      parser.parse([
        'fill',
        '--key',
        'a',
        '--',
        '--session-name',
      ]).params['input'],
      '--session-name',
    );
  });
  test('policy confirmation is session-bound, one-use, and cannot bypass nested denial', () async {
    final policy = {
      'confirm': ['tap'],
    };
    final queued = await manager.handle(
      Request(
        requestId: 'policy',
        session: 'a',
        command: 'tap',
        params: {'key': 'a'},
        deadline: DateTime.now().add(const Duration(seconds: 10)),
        policy: policy,
      ),
    );
    expect(queued.error!.code, 'CONFIRMATION_REQUIRED');
    expect(backend.calls, isNot(contains('tap')));
    final id = queued.error!.details!['confirmationId'];
    final confirmed = await manager.handle(
      Request(
        requestId: 'approval',
        session: 'a',
        command: 'confirm',
        params: {'id': id},
        deadline: DateTime.now().add(const Duration(seconds: 10)),
        policy: policy,
      ),
    );
    expect(confirmed.exitCode, 0);
    expect(backend.calls.where((call) => call == 'tap').length, 1);
    expect(
      (await manager.handle(request('confirm', params: {'id': id})))
          .error!
          .code,
      'INVALID_ARGUMENT',
    );
    final batch = await manager.handle(
      Request(
        requestId: 'batch',
        session: 'a',
        command: 'batch',
        params: {
          'steps': [
            {
              'command': 'tap',
              'params': {'key': 'a'},
            },
          ],
        },
        deadline: DateTime.now().add(const Duration(seconds: 10)),
        policy: {
          'deny': ['tap'],
        },
      ),
    );
    expect(batch.error!.code, 'ACTION_DENIED');
    expect(backend.calls.where((call) => call == 'tap').length, 1);
  });
  test(
    'batch stops after failure and reports completed steps without resending',
    () async {
      final result = await manager.handle(
        request(
          'batch',
          params: {
            'steps': [
              {
                'command': 'tap',
                'params': {'key': 'a'},
              },
              {
                'command': 'tap',
                'params': {'key': 'absent'},
              },
              {
                'command': 'tap',
                'params': {'key': 'a'},
              },
            ],
          },
        ),
      );
      expect(result.error!.details!['completed'], 1);
      expect(backend.calls.where((call) => call == 'tap').length, 1);
    },
  );
  test('snapshot diff ignores ref numbering and compares repeated rows as a multiset', () async {
    final baseline = utf8.encode(
      jsonEncode({
        'elements': [
          {'ref': '@e1', 'text': 'a'},
          {'ref': '@e2', 'text': 'a'},
        ],
      }),
    );
    final result = await compareObservation(
      {'action': 'snapshot'},
      baseline,
      {
        'generation': 3,
        'elements': [
          {'ref': '@e9', 'text': 'a'},
        ],
      },
      DateTime.now().add(const Duration(seconds: 5)),
    );
    expect(result['changed'], true);
    expect((result['removed'] as List).length, 1);
    expect(result['added'], isEmpty);
  });
  test(
    'PNG diff and crop verify pixels, geometry and no-overwrite behavior',
    () async {
      final before = img.Image(width: 4, height: 4, numChannels: 4);
      final after = before.clone()..setPixelRgba(1, 1, 255, 0, 0, 255);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      final result = await compareObservation(
        {'action': 'screenshot', 'threshold': 0},
        img.encodePng(before),
        {
          'images': [base64Encode(img.encodePng(after))],
        },
        deadline,
      );
      expect(result['changedPixels'], 1);
      final path = '${files.path}/crop.png';
      final data = {
        'images': [base64Encode(img.encodePng(after))],
        'geometry': geometry(width: 4, height: 4, scale: 1),
        'crop': {'x': 1, 'y': 1, 'width': 2, 'height': 2},
      };
      expect((await saveScreenshots(data, path, deadline))['cropped'], true);
      final crop = img.decodePng(await File(path).readAsBytes())!;
      expect(crop.width, 2);
      expect(crop.getPixel(0, 0).r, 255);
      await expectLater(
        saveScreenshots(data, path, deadline),
        throwsA(isA<AgentError>().having((e) => e.code, 'code', 'IO_ERROR')),
      );
      await expectLater(
        saveScreenshots(
          {
            ...data,
            'crop': {'x': -1, 'y': 1, 'width': 2, 'height': 2},
          },
          '${files.path}/invalid.png',
          deadline,
        ),
        throwsA(isA<AgentError>()),
      );
    },
  );
}
