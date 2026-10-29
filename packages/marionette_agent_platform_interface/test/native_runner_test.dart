import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_platform_interface/host_support.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ServerSocket server;
  late File config;
  final requests = <Map<String, dynamic>>[];
  final clients = <Socket>[];
  late Future<void> Function(Socket, Map<String, dynamic>) respond;
  const token = '0123456789abcdef0123456789abcdef';
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 2));
  setUp(() async {
    requests.clear();
    clients.clear();
    directory = await Directory.systemTemp.createTemp('native-runner-');
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    config = File('${directory.path}/runners.json');
    await config.writeAsString(
      jsonEncode({
        for (final platform in ['ios', 'android'])
          platform: {
            'device': {'port': server.port, 'token': token},
          },
      }),
    );
    respond = (socket, request) async {
      socket.writeln(
        jsonEncode({
          'version': 1,
          'platform': request['platform'],
          'device': request['device'],
          'ok': true,
          'elements': [
            {
              'type': 'Button',
              'text': 'Allow',
              'identifier': null,
              'value': '',
              'package': 'system',
              'enabled': true,
              'bounds': {'x': 10, 'y': 20.5, 'width': 100, 'height': 40},
            },
          ],
        }),
      );
      await socket.flush();
    };
    server.listen((socket) async {
      clients.add(socket);
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      final request = jsonDecode(line) as Map<String, dynamic>;
      requests.add(request);
      await respond(socket, request);
    });
  });
  tearDown(() async {
    for (final socket in clients) {
      socket.destroy();
    }
    await server.close();
    await directory.delete(recursive: true);
  });
  NativeRunnerUi backend([String platform = 'android']) =>
      NativeRunnerUi(platform: platform, configurationPath: config.path);
  Matcher error(String code) =>
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

  for (final platform in ['ios', 'android']) {
    test(
      '$platform sends explicit identity and preserves normalized bounds',
      () async {
        final until = deadline();
        final nodes = await backend(platform).inspect('device', until);
        expect(nodes.single.text, 'Allow');
        expect(nodes.single.identifier, isNull);
        expect(nodes.single.value, isNull);
        expect(nodes.single.bounds.y, 20.5);
        await backend(platform).tap('device', 60.5, 40.5, until);
        await backend(platform).swipe('device', 10.5, 20, 30, 40, until);
        expect(requests.map((e) => e['action']), ['snapshot', 'tap', 'swipe']);
        for (final request in requests) {
          expect(request['token'], token);
          expect(request['platform'], platform);
          expect(request['device'], 'device');
          expect(request['deadline'], until.millisecondsSinceEpoch);
        }
        expect(requests[1]['x'], 60.5);
        expect(requests[2]['startX'], 10.5);
      },
    );
  }
  test('missing device configuration never connects', () async {
    await expectLater(
      backend().tap('other', 1, 2, deadline()),
      error('UNSUPPORTED_CAPABILITY'),
    );
    expect(requests, isEmpty);
  });
  test(
    'wrong device response and malformed observations fail closed',
    () async {
      respond = (socket, request) async {
        socket.writeln(
          jsonEncode({
            'version': 1,
            'platform': 'android',
            'device': 'other',
            'ok': true,
          }),
        );
        await socket.flush();
      };
      await expectLater(
        backend().inspect('device', deadline()),
        error('BACKEND_ERROR'),
      );
      respond = (socket, request) async {
        socket.writeln(
          jsonEncode({
            'version': 1,
            'platform': 'android',
            'device': 'device',
            'ok': true,
            'elements': [{}],
          }),
        );
        await socket.flush();
      };
      await expectLater(
        backend().inspect('device', deadline()),
        error('BACKEND_ERROR'),
      );
    },
  );
  test('runner errors never echo private screen text', () async {
    respond = (socket, request) async {
      socket.writeln(
        jsonEncode({
          'version': 1,
          'platform': 'android',
          'device': 'device',
          'ok': false,
          'code': 'secret-screen-text',
          'message': token,
        }),
      );
      await socket.flush();
    };
    await expectLater(
      backend().tap('device', 1, 2, deadline()),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'BACKEND_ERROR')
            .having(
              (e) => e.message,
              'message',
              allOf(
                isNot(contains(token)),
                isNot(contains('secret-screen-text')),
              ),
            ),
      ),
    );
    expect(requests, hasLength(1));
  });
  test(
    'timeout closes connection without replay; expired call never sends',
    () async {
      respond = (socket, request) async {};
      await expectLater(
        backend().tap(
          'device',
          1,
          2,
          DateTime.now().add(const Duration(milliseconds: 150)),
        ),
        error('TIMEOUT'),
      );
      expect(requests, hasLength(1));
      await expectLater(
        backend().tap(
          'device',
          1,
          2,
          DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        error('TIMEOUT'),
      );
      expect(requests, hasLength(1));
    },
  );
}
