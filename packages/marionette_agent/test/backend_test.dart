import 'package:marionette_agent/src/backend/backend.dart';
import 'package:marionette_agent/src/backend/marionette_backend.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

class ConnectorFixture extends VmServiceConnector {
  Map<String, dynamic> args = {};
  Object? failure;
  Map<String, dynamic> response = {'status': 'Success', 'message': 'arbitrary'};
  Future<Map<String, dynamic>> call(Map<String, dynamic> input) async {
    args = input;
    if (failure != null) throw failure!;
    return response;
  }

  @override
  Future<Map<String, dynamic>> tap(Map<String, dynamic> matcher) =>
      call(matcher);
  @override
  Future<Map<String, dynamic>> swipe(Map<String, dynamic> args) => call(args);
  @override
  Future<Map<String, dynamic>> enterText(
    Map<String, dynamic> matcher,
    String input,
  ) => call({...matcher, 'input': input});
  @override
  Future<Map<String, dynamic>> getInteractiveElements() => call({});
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
  test('mapped capture validates capability at the adapter boundary', () async {
    final connector = ConnectorFixture();
    final backend = MarionetteBackend(connector: connector);
    final geometry = <String, Object?>{
      'version': 1,
      'viewCount': 1,
      'viewId': '0',
      'rotation': 0,
      'originX': 0,
      'originY': 0,
      'pixelWidth': 400,
      'pixelHeight': 600,
      'logicalWidth': 200,
      'logicalHeight': 300,
    };
    connector.response = {
      'status': 'Success',
      'supported': true,
      'screenshots': ['png'],
      'geometry': geometry,
    };
    expect((await backend.captureMappedScreenshot()).geometry.width, 400);
    expect(connector.args, {
      'extension': 'marionette_agent.captureMappedScreenshot',
    });
    for (final change in <Map<String, dynamic>>[
      {'supported': false},
      {
        'screenshots': ['one', 'two'],
      },
      {
        'geometry': {...geometry, 'rotation': 90},
      },
      {'geometry': {}},
    ]) {
      connector.response = {...connector.response, ...change};
      await expectLater(
        backend.captureMappedScreenshot(),
        throwsA(
          isA<AgentError>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_CAPABILITY',
          ),
        ),
      );
      connector.response = {
        'status': 'Success',
        'supported': true,
        'screenshots': ['png'],
        'geometry': geometry,
      };
    }
    connector.failure = VmServiceExtensionException(
      'private',
      errorCode: -32601,
      error: 'private',
    );
    await expectLater(
      backend.captureMappedScreenshot(),
      throwsA(
        isA<AgentError>()
            .having((e) => e.code, 'code', 'UNSUPPORTED_CAPABILITY')
            .having(
              (e) => e.toString(),
              'diagnostic',
              isNot(contains('private')),
            ),
      ),
    );
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
      'screenshots': ['abc'],
    };
    expect(await b.captureScreenshots(), ['abc']);
    c.response = {
      'status': 'Success',
      'logs': ['one', 'two'],
    };
    expect((await b.readLogs()).entries, ['one', 'two']);
    c.failure = VmServiceExtensionException(
      'error',
      errorCode: -32000,
      error: 'Log collection is not configured.',
    );
    expect((await b.readLogs()).configured, false);
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
