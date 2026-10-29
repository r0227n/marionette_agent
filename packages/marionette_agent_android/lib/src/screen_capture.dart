import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

/// Explicit pairing with a separately started UI Automator instrumentation.
/// No host device command, shell, forwarding, or image-capture fallback.
class AndroidScreenCapturer implements ScreenCapturer {
  const AndroidScreenCapturer();
  static final _captures = <String, Future<void>>{};

  @override
  Future<DeviceScreenshot> capture(
    String device,
    DateTime deadline, {
    String? source,
  }) async {
    final previous = _captures[device] ?? Future<void>.value();
    final request = previous.then((_) => _request(device, deadline, 'capture'));
    final settled = request.then<void>((_) {}, onError: (Object _) {});
    _captures[device] = settled;
    unawaited(
      settled.whenComplete(() {
        if (identical(_captures[device], settled)) _captures.remove(device);
      }),
    );
    final result = await request;
    return DeviceScreenshot(
      png: result.png,
      source: 'android-emulator',
      method: 'uiautomator',
      device: result.device,
      runtime: 'android-emulator',
      display: '0',
      mask: 'system-default',
    );
  }

  @override
  Future<void> dispose() async {}

  Future<void> stopAgent(String pairingFile, DateTime deadline) async {
    await _request(pairingFile, deadline, 'stop');
  }

  Future<({String device, Uint8List png})> _request(
    String file,
    DateTime deadline,
    String command,
  ) async {
    ServerSocket? server;
    Socket? socket;
    _Reader? reader;
    Duration remaining() {
      final value = deadline.difference(DateTime.now());
      if (value <= Duration.zero) throw TimeoutException('deadline');
      return value;
    }

    try {
      final pairing = await CapturePairing.read(file).timeout(remaining());
      final binding = ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        pairing.port,
      );
      var expired = false;
      unawaited(
        binding.then((late) async {
          if (expired) await late.close();
        }, onError: (Object _) {}),
      );
      try {
        server = await binding.timeout(remaining());
      } on SocketException {
        throw const PlatformException(
          'SESSION_CONFLICT',
          'Cannot reserve the paired UI Automator port',
        );
      } finally {
        expired = true;
      }
      final accepting = server.first;
      var acceptExpired = false;
      unawaited(
        accepting.then((late) {
          if (acceptExpired) late.destroy();
        }, onError: (Object _) {}),
      );
      try {
        socket = await accepting.timeout(remaining());
      } finally {
        acceptExpired = true;
      }
      reader = _Reader(socket);
      final random = Random.secure();
      final nonce = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      socket.add(_frame({'version': 1, 'nonce': nonce}));
      await socket.flush().timeout(remaining());
      final hello = await reader.json(deadline);
      if (hello['version'] != 1 ||
          !_matches(hello['proof'], _proof(pairing.token, 'agent:$nonce')) ||
          hello['device'] != pairing.device) {
        throw const PlatformException(
          'IO_ERROR',
          'UI Automator pairing failed',
        );
      }
      if (hello['emulator'] != true || jsonEncode(hello['displays']) != '[0]') {
        throw const PlatformException(
          'UNSUPPORTED_CAPABILITY',
          'UI Automator capture supports an Emulator with only display 0',
        );
      }
      socket.add(
        _frame({
          'version': 1,
          'command': command,
          'proof': _proof(pairing.token, 'host:$nonce:$command'),
        }),
      );
      await socket.flush().timeout(remaining());
      final response = await reader.json(deadline);
      if (response['ok'] != true) {
        final code = response['code'];
        throw PlatformException(
          ['UNSUPPORTED_CAPABILITY', 'IO_ERROR'].contains(code)
              ? code as String
              : 'IO_ERROR',
          'UI Automator could not capture the display',
        );
      }
      if (command == 'stop') return (device: pairing.device, png: Uint8List(0));
      final size = response['length'];
      if (size is! int || size < 1 || size > 32 * 1024 * 1024) {
        throw const PlatformException(
          'IO_ERROR',
          'Invalid UI Automator image length',
        );
      }
      final png = await reader.read(size, deadline);
      remaining();
      return (device: pairing.device, png: png);
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'UI Automator capture deadline exceeded',
        hint: 'Start the paired instrumentation on the Emulator; capture is never retried',
      );
    } on PlatformException {
      rethrow;
    } on SocketException catch (error) {
      throw PlatformException(
        error.osError?.errorCode == 48 ? 'SESSION_CONFLICT' : 'CONNECTION_LOST',
        'Cannot use the paired UI Automator connection',
      );
    } catch (_) {
      throw const PlatformException(
        'IO_ERROR',
        'Invalid UI Automator response',
      );
    } finally {
      socket?.destroy();
      await reader?.close();
      await server?.close();
    }
  }
}

/// Pairing files are private local capabilities, never sent to diagnostics.
class CapturePairing {
  const CapturePairing(this.device, this.port, this.token);
  final String device, token;
  final int port;

  static Future<CapturePairing> read(String path) async {
    try {
      final file = File(path);
      if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file ||
          (await file.stat()).mode & 0x3f != 0 ||
          await file.length() > 4096) {
        throw const FormatException();
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map ||
          data['version'] != 1 ||
          data['device'] is! String ||
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')
              .hasMatch(data['device'] as String) ||
          data['port'] is! int ||
          data['port'] < 1024 ||
          data['port'] > 65535 ||
          data['token'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['token'] as String)) {
        throw const FormatException();
      }
      return CapturePairing(
        data['device'] as String,
        data['port'] as int,
        data['token'] as String,
      );
    } catch (_) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'Use a valid private UI Automator pairing file as --device',
      );
    }
  }
}

String _proof(String token, String message) => Hmac(sha256, [
  for (var i = 0; i < token.length; i += 2)
    int.parse(token.substring(i, i + 2), radix: 16),
]).convert(utf8.encode(message)).toString();

bool _matches(Object? actual, String expected) {
  if (actual is! String || actual.length != expected.length) return false;
  var difference = 0;
  for (var i = 0; i < expected.length; i++) {
    difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return difference == 0;
}

Uint8List _frame(Map<String, Object?> value) {
  final bytes = utf8.encode(jsonEncode(value));
  return (BytesBuilder()
        ..add((ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List())
        ..add(bytes))
      .takeBytes();
}

class _Reader {
  _Reader(Stream<Uint8List> stream) : iterator = StreamIterator(stream);
  final StreamIterator<Uint8List> iterator;
  Uint8List chunk = Uint8List(0);
  int offset = 0;
  Future<Uint8List> read(int size, DateTime deadline) async {
    final result = Uint8List(size);
    var written = 0;
    while (written < size) {
      if (offset == chunk.length) {
        if (!await iterator.moveNext().timeout(
          deadline.difference(DateTime.now()),
        )) {
          throw const PlatformException(
            'CONNECTION_LOST',
            'UI Automator disconnected during capture',
          );
        }
        chunk = iterator.current;
        offset = 0;
      }
      final count = (size - written) < (chunk.length - offset)
          ? size - written
          : chunk.length - offset;
      result.setRange(written, written + count, chunk, offset);
      offset += count;
      written += count;
    }
    return result;
  }

  Future<Map<String, dynamic>> json(DateTime deadline) async {
    final length = ByteData.sublistView(await read(4, deadline)).getUint32(0);
    if (length < 2 || length > 8192) throw const FormatException();
    final value = jsonDecode(utf8.decode(await read(length, deadline)));
    if (value is! Map<String, dynamic>) throw const FormatException();
    return value;
  }

  Future<void> close() => iterator.cancel();
}
