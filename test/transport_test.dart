import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_agent/src/daemon/client.dart';
import 'package:marionette_agent/src/daemon/runtime.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:test/test.dart';

import 'support/requests.dart';

void main() {
  late Directory directory;
  late RuntimeDirectory runtime;
  setUp(() async {
    directory = await Directory('/tmp').createTemp('mra-wire-');
    await Process.run('chmod', ['700', directory.path]);
    runtime = await RuntimeDirectory.prepare(directory: directory.path);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('disconnect after request is unknown and never resent', () async {
    final server = await ServerSocket.bind(
      InternetAddress(runtime.socket, type: InternetAddressType.unix),
      0,
    );
    var received = 0;
    server.listen((socket) async {
      socket.add(
        encodeFrame({
          'protocolVersion': protocolVersion,
          'instance': 'test',
          'ready': true,
        }),
      );
      await decodeFrames(socket).first;
      received++;
      socket.destroy();
    });
    final result = await DaemonClient(runtime).send(request('write'));
    expect(result.error!.outcome, Outcome.unknown);
    expect(received, 1);
    await server.close();
  });
  test('protocol mismatch fails before sending any command', () async {
    final server = await ServerSocket.bind(
      InternetAddress(runtime.socket, type: InternetAddressType.unix),
      0,
    );
    server.listen((socket) async {
      socket.add(
        encodeFrame({'protocolVersion': 99, 'instance': 'old', 'ready': true}),
      );
      await socket.flush();
      await socket.close();
    });
    final result = await DaemonClient(runtime)
        .send(request('connect', params: {'uri': 'http://host/'}));
    expect(result.error!.code, 'IO_ERROR');
    expect(result.error!.outcome, Outcome.notSent);
    await server.close();
  });
  test(
    'size limiter rejects unterminated 64 MiB before JSON decoding',
    () async {
      final chunk = Uint8List(65536)..fillRange(0, 65536, 32);
      await expectLater(
        decodeFrames(Stream.fromIterable(List.filled(1024, chunk))).toList(),
        throwsA(
          isA<AgentError>().having(
            (error) => error.message,
            'message',
            contains('64 MiB'),
          ),
        ),
      );
    },
  );
  test('rejects world-readable runtime and symbolic-link runtime', () async {
    await Process.run('chmod', ['755', directory.path]);
    await expectLater(
      RuntimeDirectory.prepare(directory: directory.path),
      throwsA(isA<AgentError>()),
    );
    await Process.run('chmod', ['700', directory.path]);
    final link = Link('${directory.path}/alias');
    await link.create(directory.path);
    await expectLater(
      RuntimeDirectory.prepare(directory: link.path),
      throwsA(isA<AgentError>()),
    );
  });
}
