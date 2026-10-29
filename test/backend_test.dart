import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/connection_uri.dart';
import 'package:marionette_agent/src/backend/marionette_backend.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

class ConnectorFixture extends VmServiceConnector {
  Map<String, dynamic> args = {};
  Object? failure;
  bool extended = false;
  String? version = '0.6.0';
  bool hasExtensionRegistry = true;
  int actionCalls = 0;
  static final missingMethod = VmServiceExtensionException(
    'missing',
    errorCode: -32601,
  );
  @override
  Future<String> getVersion() async => version ?? (throw missingMethod);
  @override
  Future<void> connect(String uri) async {}
  @override
  Future<Map<String, dynamic>> listExtensions() async => !hasExtensionRegistry
      ? (throw missingMethod)
      : {
          'status': 'Success',
          'extensions': [
            if (extended) {'name': 'marionette_agent.inspect'},
          ],
        };
  Map<String, dynamic> response = {'status': 'Success', 'message': 'arbitrary'};
  Future<Map<String, dynamic>> call(Map<String, dynamic> input) async {
    args = input;
    if (failure != null) throw failure!;
    return response;
  }

  @override
  Future<Map<String, dynamic>> tap(Map<String, dynamic> matcher) {
    actionCalls++;
    return call(matcher);
  }

  @override
  Future<Map<String, dynamic>> swipe(Map<String, dynamic> args) => call(args);
  @override
  Future<Map<String, dynamic>> enterText(
    Map<String, dynamic> matcher,
    String input,
  ) => call({...matcher, 'input': input});
  @override
  Future<Map<String, dynamic>> getInteractiveElements({
    List<String> ancestorKeys = const [],
    String? compaction,
  }) => call({'compaction': ?compaction});
  @override
  Future<Map<String, dynamic>> takeScreenshots() => call({});
  @override
  Future<Map<String, dynamic>> getLogs() => call({});
  @override
  Future<Map<String, dynamic>> callCustomExtension(
    String name, [
    Map<String, dynamic> args = const {},
  ]) => call({'extension': name});
}

void main() {
  group('published binding compatibility', () {
    for (final legacyType in [false, true]) {
      test(
        'pre-0.4 discovery, health and ${legacyType ? 'VM envelope' : 'status'} responses',
        () async {
          final c = ConnectorFixture()
            ..version = null
            ..hasExtensionRegistry = false
            ..response = {
              if (legacyType) ...{
                'type': '_extensionType',
                'method': 'ext.flutter.marionette.interactiveElements',
              } else
                'status': 'Success',
              'elements': [
                {
                  'type': 'Text',
                  'key': 'result',
                  if (legacyType) 'text': 'Count: 1' else 'data': 'Count: 1',
                  'visible': true,
                },
              ],
            };
          final b = MarionetteBackend(connector: c);
          await b.connect(Uri.parse('ws://localhost:1234/ws'));
          expect((await b.inspect()).single.text, 'Count: 1');
          await b.checkConnection();
          expect(b.selectors.contains(SelectorKind.type), !legacyType);
          c.response = {
            if (legacyType) ...{
              'type': '_extensionType',
              'method': 'ext.flutter.marionette.tap',
              'message': 'anything',
            } else
              'status': 'Success',
          };
          await b.tap(
            const ElementTarget(Selector(SelectorKind.key, 'button')),
          );
          expect(c.actionCalls, 1);
          c.response = {
            if (legacyType) ...{
              'type': '_extensionType',
              'method': 'ext.flutter.marionette.tap',
              'error': 'private',
            } else
              'status': 'Error',
            'message': 'Success',
          };
          await expectLater(
            b.tap(const ElementTarget(Selector(SelectorKind.key, 'button'))),
            throwsA(isA<AgentError>()),
          );
          expect(
            c.actionCalls,
            2,
            reason: 'Failed actions must never be resent',
          );
          if (legacyType) {
            expect(
              () => b.tap(CoordinateTarget(Point(1, 2))),
              throwsA(
                isA<AgentError>().having(
                  (e) => e.code,
                  'code',
                  'UNSUPPORTED_CAPABILITY',
                ),
              ),
            );
            expect(c.actionCalls, 2);
          }
        },
      );
    }
    test(
      '0.7 requests explicit visibility and preserves identifier matcher data',
      () async {
        final c = ConnectorFixture()..version = '0.7.0';
        final b = MarionetteBackend(connector: c);
        await b.connect(Uri.parse('ws://localhost:1234/ws'));
        c.response = {
          'status': 'Success',
          'elements': [
            {
              'type': 'Text',
              'text': 'Save',
              'identifier': 'save',
              'visible': true,
            },
          ],
        };
        final e = (await b.inspect()).single;
        expect(e.visible, true);
        expect(e.identifier, 'save');
        expect(c.args, {'compaction': 'none'});
        c.response = {'status': 'Success'};
        await b.tap(
          const ElementTarget(Selector(SelectorKind.identifier, 'save')),
        );
        expect(c.args, {'identifier': 'save'});
      },
    );
    test(
      'discovery errors other than missing methods are not ignored',
      () async {
        final c = ConnectorFixture()..version = null;
        c.failure = VmServiceExtensionException('private', errorCode: -32010);
        await expectLater(
          MarionetteBackend(connector: c)
              .connect(Uri.parse('ws://localhost:1234/ws')),
          throwsA(
            isA<AgentError>().having((e) => e.code, 'code', 'CONNECTION_LOST'),
          ),
        );
      },
    );
  });
  group('inspect provider contracts', () {
    late ConnectorFixture connector;
    late MarionetteBackend backend;
    final bounds = {'x': 0, 'y': 0, 'width': 48, 'height': 48};
    final button = <String, dynamic>{
      'type': 'FilledButton',
      'key': 'camera.replay.sample',
      'visible': true,
      'bounds': bounds,
      'enabled': 'true',
    };
    final backendError = throwsA(
      isA<AgentError>().having((e) => e.code, 'code', 'BACKEND_ERROR'),
    );

    setUp(() {
      connector = ConnectorFixture();
      backend = MarionetteBackend(connector: connector);
    });

    Future<void> connect({bool extended = false}) async {
      connector.extended = extended;
      connector.response = {
        'status': 'Success',
        'version': 1,
        'interactions': <String>[],
      };
      await backend.connect(Uri.parse('ws://localhost:1234/ws'));
    }

    void respond(List<Object?> elements) {
      connector.response = {'status': 'Success', 'elements': elements};
    }

    test(
      'legacy buttons retain protocol attributes, not string diagnostics',
      () async {
        await connect();
        // Representative rows from the reported binding 0.6.0 response:
        // debugFillProperties values are strings; visible/bounds are protocol data.
        respond([
          button,
          {
            ...button,
            'type': 'OutlinedButton',
            'key': 'camera.mock.imagePicker',
          },
          {'type': 'Text', 'text': 'Replay sample', 'visible': true},
          {'type': 'Semantics', 'text': 'Camera', 'visible': false},
        ]);
        final elements = await backend.inspect();
        expect(elements.map((e) => e.toJson()), [
          {
            'type': 'FilledButton',
            'key': 'camera.replay.sample',
            'visible': true,
            'bounds': bounds,
          },
          {
            'type': 'OutlinedButton',
            'key': 'camera.mock.imagePicker',
            'visible': true,
            'bounds': bounds,
          },
          {'type': 'Text', 'text': 'Replay sample', 'visible': true},
          {'type': 'Semantics', 'text': 'Camera', 'visible': false},
        ]);
        expect(elements.map((e) => e.textMatchable), [
          false,
          false,
          true,
          false,
        ]);
        expect(connector.args, {'compaction': 'none'});
      },
    );

    test('legacy diagnostic names never become typed observations', () async {
      await connect();
      for (final diagnostics in [
        {
          'enabled': 'false',
          'checked': 'true',
          'interactive': 'true',
          'depth': '3',
        },
        {'enabled': true, 'checked': false, 'interactive': true, 'depth': 3},
      ]) {
        respond([
          {
            'type': 'CustomWidget',
            ...diagnostics,
            'identifier': 'diagnostic id',
            'inputValue': 'diagnostic value',
            'role': 'button',
            'label': 'diagnostic label',
            'placeholder': 'diagnostic placeholder',
          },
        ]);
        expect((await backend.inspect()).single.toJson(), {
          'type': 'CustomWidget',
        });
      }
    });

    test(
      'legacy protocol attributes and envelopes still reject malformed values',
      () async {
        await connect();
        for (final row in <Object?>[
          null,
          'element',
          {1: 'value'},
          {'type': 1},
          {'text': false},
          {'key': []},
          {'visible': 'true'},
          {'bounds': 'diagnostic'},
          {
            'bounds': {...bounds, 'width': -1},
          },
        ]) {
          respond([row]);
          await expectLater(backend.inspect(), backendError);
        }
        for (final response in <Map<String, dynamic>>[
          {'status': 'Failure', 'elements': []},
          {'elements': []},
          {'status': 'Success', 'elements': {}},
        ]) {
          connector.response = response;
          await expectLater(backend.inspect(), backendError);
        }
      },
    );

    test('typed provider preserves typed attributes and rejects string diagnostics', () async {
      await connect(extended: true);
      final typed = {
        ...button,
        'enabled': true,
        'checked': false,
        'interactive': true,
        'depth': 3,
        'identifier': 'camera',
        'inputValue': '',
        'role': 'button',
        'label': 'Replay',
        'placeholder': 'Choose sample',
      };
      respond([typed]);
      expect((await backend.inspect()).single.toJson(), typed);
      expect(connector.args, {'extension': 'marionette_agent.inspect'});
      for (final field in [
        'visible',
        'enabled',
        'checked',
        'interactive',
        'depth',
      ]) {
        respond([
          {...typed, field: 'true'},
        ]);
        await expectLater(backend.inspect(), backendError);
      }
      respond([button]);
      await expectLater(backend.inspect(), backendError);
    });
  });

  test('URI preserves authentication and normalizes websocket suffix', () {
    expect(
      normalizeUri('https://localhost:123/token/?auth=secret').toString(),
      'wss://localhost:123/token/ws?auth=secret',
    );
    expect(normalizeUri('ws://localhost/token/ws/').path, '/token/ws');
    expect(
      redactUri(normalizeUri('http://user:pass@localhost/token/?secret=yes')),
      isNot(contains('secret')),
    );
    for (final uri in ['file:///x', 'http:///', 'https://host/#fragment']) {
      expect(() => normalizeUri(uri), throwsA(isA<AgentError>()));
    }
  });
  test(
    'fixed connector methods map typed primitives to wire strings',
    () async {
      final c = ConnectorFixture();
      final b = MarionetteBackend(connector: c);
      await b.swipe(
        ElementSwipe(const Selector(SelectorKind.key, 'pager'), Direction.left),
      );
      expect(c.args, {
        'key': 'pager',
        'direction': 'left',
        'distance': '200.0',
      });
      await b.swipe(CoordinateSwipe(Point(1, 2), Point(3, 4)));
      expect(c.args, {
        'startX': '1.0',
        'startY': '2.0',
        'endX': '3.0',
        'endY': '4.0',
      });
      await b.tap(CoordinateTarget(Point(2, 3)));
      expect(c.args, {'x': '2.0', 'y': '3.0'});
      await b.fill(const Selector(SelectorKind.key, 'input'), '');
      expect(c.args, {'key': 'input', 'input': ''});
      expect(
        () =>
            b.tap(const ElementTarget(Selector(SelectorKind.identifier, 'id'))),
        throwsA(
          isA<AgentError>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_CAPABILITY',
          ),
        ),
      );
    },
  );
  test('response status, error sanitization, image/log shapes', () async {
    final c = ConnectorFixture();
    final b = MarionetteBackend(connector: c);
    c.response = {'message': 'Success'};
    await expectLater(
      b.tap(CoordinateTarget(Point(0, 0))),
      throwsA(isA<AgentError>()),
    );
    c.failure = VmServiceExtensionException(
      'secret input',
      errorCode: -32601,
      error: 'secret URI',
    );
    await expectLater(
      b.inspect(),
      throwsA(
        isA<AgentError>()
            .having((e) => e.code, 'code', 'UNSUPPORTED_CAPABILITY')
            .having((e) => e.toString(), 'safe', isNot(contains('secret'))),
      ),
    );
    c.failure = null;
    c.response = {
      'status': 'Success',
      'logs': ['one', 'two'],
    };
    expect((await b.readLogs()).entries, ['one', 'two']);
    for (final code in [-32000, -32016]) {
      c.failure = VmServiceExtensionException(
        'error',
        errorCode: code,
        error: 'Log collection is not configured.',
      );
      expect((await b.readLogs()).configured, false);
    }
  });
  test('Semantics text stays readable but not text-matchable', () {
    final elements = MarionetteBackend.decodeElements({
      'status': 'Success',
      'elements': [
        {'type': 'Semantics', 'text': 'Save', 'visible': true},
        {'type': 'Text', 'text': 'Save'},
        {
          'type': 'Button',
          'key': 'save',
          'bounds': {'x': 0, 'y': 1, 'width': 2, 'height': 3},
        },
      ],
    });
    expect(elements.first.text, 'Save');
    expect(elements.first.textMatchable, false);
    expect(elements[1].textMatchable, true);
    expect(elements[2].toJson().containsKey('visible'), false);
    expect(
      () => MarionetteBackend.decodeElements({
        'status': 'Success',
        'elements': [
          {'visible': 'yes'},
        ],
      }),
      throwsA(isA<AgentError>()),
    );
  });
  test('fixed vm_service disposal errors are connection loss, never definite failure', () async {
    final c = ConnectorFixture();
    final b = MarionetteBackend(connector: c);
    for (final code in [-32000, -32010, 112]) {
      c.failure = VmServiceExtensionException(
        'safe',
        errorCode: code,
        error: 'Service connection disposed',
      );
      await expectLater(
        b.inspect(),
        throwsA(
          isA<AgentError>().having((e) => e.code, 'code', 'CONNECTION_LOST'),
        ),
      );
    }
  });
}
