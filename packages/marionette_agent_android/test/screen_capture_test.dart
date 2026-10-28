import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:test/test.dart';

String proof(String text) =>
    Hmac(sha256, List.filled(32, 0xab)).convert(utf8.encode(text)).toString();
List<int> frame(Map<String, Object?> value) {
  final body = utf8.encode(jsonEncode(value));
  return [
    ...(ByteData(4)..setUint32(0, body.length)).buffer.asUint8List(),
    ...body,
  ];
}

class Reader {
  Reader(Socket socket) : iterator = StreamIterator(socket);
  final StreamIterator<Uint8List> iterator;
  final bytes = <int>[];
  Future<List<int>> read(int n) async {
    while (bytes.length < n) {
      if (!await iterator.moveNext()) throw const SocketException('EOF');
      bytes.addAll(iterator.current);
    }
    final result = bytes.sublist(0, n);
    bytes.removeRange(0, n);
    return result;
  }

  Future<Map<String, dynamic>> json() async {
    final n = ByteData.sublistView(Uint8List.fromList(await read(4)))
        .getUint32(0);
    return jsonDecode(utf8.decode(await read(n))) as Map<String, dynamic>;
  }
}

void main() {
  late Directory directory;
  late File file;
  late int port;
  var requests = 0;
  const capturer = AndroidScreenCapturer();
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 3));
  Future<void> agent({
    String identity = 'fixture',
    bool emulator = true,
    List<int> displays = const [0],
    bool badProof = false,
    String? error,
    int? length,
    bool disconnect = false,
    bool malformed = false,
  }) async {
    Socket socket;
    final until = deadline();
    while (true) {
      try {
        socket = await Socket.connect('127.0.0.1', port);
        break;
      } on SocketException {
        if (DateTime.now().isAfter(until)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    final reader = Reader(socket);
    try {
      final challenge = await reader.json();
      expect(challenge.containsKey('token'), false);
      final nonce = challenge['nonce'] as String;
      socket.add(
        frame({
          'version': 1,
          'device': identity,
          'proof': badProof ? 'bad' : proof('agent:$nonce'),
          'emulator': emulator,
          'displays': displays,
        }),
      );
      await socket.flush();
      if (badProof ||
          identity != 'fixture' ||
          !emulator ||
          displays.length != 1 ||
          displays.single != 0) {
        try {
          await reader.iterator.moveNext();
        } on SocketException {
          /* Rejected peer is disconnected before any capture. */
        }
        return;
      }
      final command = await reader.json();
      expect(command['proof'], proof('host:$nonce:${command['command']}'));
      requests++;
      if (command['command'] == 'stop') {
        socket.add(frame({'ok': true}));
        return;
      }
      if (malformed) {
        socket.add((ByteData(4)..setUint32(0, 9000)).buffer.asUint8List());
        return;
      }
      if (error != null) {
        socket.add(
          frame({
            'ok': false,
            'code': error,
            'message': 'private token must not leak',
          }),
        );
        return;
      }
      socket.add(frame({'ok': true, 'length': length ?? 5}));
      if (!disconnect) socket.add(utf8.encode('image'));
    } finally {
      await socket.flush();
      socket.destroy();
      await reader.iterator.cancel();
    }
  }

  Matcher fails(String code) => throwsA(
    isA<PlatformException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.message, 'redacted', isNot(contains('private token'))),
  );
  setUp(() async {
    requests = 0;
    directory = await Directory.systemTemp.createTemp('uia-capture-');
    file = File('${directory.path}/pairing.json');
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    port = reservation.port;
    await reservation.close();
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'device': 'fixture',
        'port': port,
        'token': 'ab' * 32,
      }),
    );
    await Process.run('chmod', ['600', file.path]);
  });
  tearDown(() => directory.delete(recursive: true));
  test(
    'paired native pixels use explicit device and mutual authentication',
    () async {
      final serving = agent();
      final image = await capturer.capture(file.path, deadline());
      await serving;
      expect(utf8.decode(image.png), 'image');
      expect(image.source, 'android-emulator');
      expect(image.method, 'uiautomator');
      expect(image.device, 'fixture');
      expect(image.display, '0');
      expect(requests, 1);
    },
  );
  for (final variant in [
    'wrong-proof',
    'wrong-device',
    'physical',
    'displays',
  ]) {
    test('$variant fails before capture is requested', () async {
      final serving = agent(
        badProof: variant == 'wrong-proof',
        identity: variant == 'wrong-device' ? 'other' : 'fixture',
        emulator: variant != 'physical',
        displays: variant == 'displays' ? [0, 2] : [0],
      );
      await expectLater(
        capturer.capture(file.path, deadline()),
        fails(
          variant.startsWith('wrong') ? 'IO_ERROR' : 'UNSUPPORTED_CAPABILITY',
        ),
      );
      await serving;
      expect(requests, 0);
    });
  }
  test('missing agent times out and releases listener', () async {
    await expectLater(
      capturer.capture(
        file.path,
        DateTime.now().add(const Duration(milliseconds: 100)),
      ),
      fails('TIMEOUT'),
    );
    final reusable = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    await reusable.close();
  });
  test('busy port cannot silently select another agent', () async {
    final other = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    try {
      await expectLater(
        capturer.capture(file.path, deadline()),
        fails('SESSION_CONFLICT'),
      );
    } finally {
      await other.close();
    }
  });
  for (final variant in ['denied', 'oversized', 'disconnected', 'malformed']) {
    test('$variant does not publish or replay a capture', () async {
      final serving = agent(
        error: variant == 'denied' ? 'IO_ERROR' : null,
        length: variant == 'oversized' ? 33 * 1024 * 1024 : null,
        disconnect: variant == 'disconnected',
        malformed: variant == 'malformed',
      );
      await expectLater(
        capturer.capture(file.path, deadline()),
        fails(variant == 'disconnected' ? 'CONNECTION_LOST' : 'IO_ERROR'),
      );
      await serving;
      expect(requests, 1);
    });
  }
  test(
    'invalid or non-private pairing is rejected without networking',
    () async {
      await expectLater(
        capturer.capture('${directory.path}/missing', deadline()),
        fails('INVALID_ARGUMENT'),
      );
      await Process.run('chmod', ['644', file.path]);
      await expectLater(
        capturer.capture(file.path, deadline()),
        fails('INVALID_ARGUMENT'),
      );
    },
  );
  test('explicit stop terminates only the paired agent', () async {
    final serving = agent();
    await capturer.stopAgent(file.path, deadline());
    await serving;
    expect(requests, 1);
  });
}
