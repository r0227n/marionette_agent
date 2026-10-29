import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/platform/platform_services.dart';
import 'package:marionette_agent_web/marionette_agent_web.dart';
import 'package:test/test.dart';

void main() {
  for (final failure in [false, true]) {
    test(
      'CDP captures page frames and ${failure ? 'fails on disconnect' : 'finalizes on stop'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final dir = await Directory.systemTemp.createTemp('cdp-record-test-');
        addTearDown(() async {
          await server.close(force: true);
          await dir.delete(recursive: true);
        });
        WebSocket? peer;
        final methods = <String>[];
        server.listen((request) async {
          peer = await WebSocketTransformer.upgrade(request);
          peer!.listen((raw) {
            final message = jsonDecode(raw as String) as Map;
            final method = message['method'] as String;
            methods.add(method);
            final result = switch (method) {
              'Browser.getVersion' => {'product': 'HeadlessChrome/150'},
              'Target.getTargetInfo' => {
                'targetInfo': {'type': 'page', 'targetId': 'ABC'},
              },
              'Page.captureScreenshot' => {
                'data': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0ioAAAAASUVORK5CYII=',
              },
              _ => <String, Object?>{},
            };
            peer!.add(jsonEncode({'id': message['id'], 'result': result}));
          });
        });
        final path = '${dir.path}/video.mp4';
        final handle = await const WebScreenRecorder().start(
          RecordingTarget(
            RecordingPlatform.web,
            'ws://127.0.0.1:${server.port}/devtools/page/ABC',
          ),
          path,
          DateTime.now().add(const Duration(seconds: 30)),
        );
        expect(methods, contains('Page.captureScreenshot'));
        if (failure) {
          await peer!.close();
          await handle.ended.timeout(const Duration(seconds: 15));
          await expectLater(
            handle.stop(),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'CONNECTION_LOST',
              ),
            ),
          );
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await handle.stop();
          await handle.stop();
          expect(await File(path).length(), greaterThan(0));
          expect(handle.isRunning, false);
        }
      },
    );
  }
  test('old whole-display target is rejected', () {
    expect(
      WebRecordingTarget.parse(
        'display:1@ws://127.0.0.1:9222/devtools/page/ABC',
      ),
      isNull,
    );
    expect(
      WebRecordingTarget.parse('ws://remote:9222/devtools/page/ABC'),
      isNull,
    );
  });
}
