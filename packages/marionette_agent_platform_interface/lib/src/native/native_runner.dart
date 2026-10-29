import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../marionette_agent_platform_interface.dart';

/// Bounded, single-send transport to an explicitly configured local test runner.
/// The runner owns OS API calls; it is installed and started outside the daemon.
class NativeRunnerUi implements NativeUiBackend {
  const NativeRunnerUi({required this.platform, this.configurationPath});
  final String platform;
  final String? configurationPath;

  @override
  Future<List<NativeElement>> inspect(String device, DateTime deadline) async {
    final result = await _request(device, deadline, {'action': 'snapshot'});
    try {
      return (result['elements'] as List).map((raw) {
        final row = raw as Map;
        final frame = row['bounds'] as Map;
        double number(String key) {
          final value = frame[key];
          if (value is! num || !value.isFinite) throw const FormatException();
          return value.toDouble();
        }

        String? optional(String key) {
          final value = row[key];
          if (value == null || value == '') return null;
          if (value is! String) throw const FormatException();
          return value;
        }

        return NativeElement(
          type: row['type'] as String,
          text: optional('text'),
          identifier: optional('identifier'),
          value: optional('value'),
          package: optional('package'),
          enabled: row['enabled'] as bool,
          bounds: NativeBounds(
            number('x'),
            number('y'),
            number('width'),
            number('height'),
          ),
        );
      }).toList();
    } catch (_) {
      throw const PlatformException(
        'BACKEND_ERROR',
        'Invalid native runner observation',
      );
    }
  }

  @override
  Future<void> tap(String device, double x, double y, DateTime deadline) async {
    await _request(device, deadline, {'action': 'tap', 'x': x, 'y': y});
  }

  @override
  Future<void> swipe(
    String device,
    double startX,
    double startY,
    double endX,
    double endY,
    DateTime deadline,
  ) async {
    await _request(device, deadline, {
      'action': 'swipe',
      'startX': startX,
      'startY': startY,
      'endX': endX,
      'endY': endY,
    });
  }

  Future<Map<String, dynamic>> _request(
    String device,
    DateTime deadline,
    Map<String, Object> command,
  ) async {
    Socket? socket;
    Duration remaining() {
      final duration = deadline.difference(DateTime.now());
      if (duration <= Duration.zero) throw TimeoutException('Native deadline');
      return duration;
    }

    try {
      final path =
          configurationPath ??
          Platform.environment['MARIONETTE_AGENT_NATIVE_RUNNERS'];
      if (path == null || path.isEmpty) {
        throw const PlatformException(
          'UNSUPPORTED_CAPABILITY',
          'Native runner is not configured',
          hint: 'Set MARIONETTE_AGENT_NATIVE_RUNNERS to the runner configuration file',
        );
      }
      final configFile = File(path);
      if (await configFile.length().timeout(remaining()) > 65536) {
        throw const FormatException();
      }
      final config = jsonDecode(
        await configFile.readAsString().timeout(remaining()),
      ) as Map;
      final entry = (config[platform] as Map?)?[device];
      if (entry == null) {
        throw const PlatformException(
          'UNSUPPORTED_CAPABILITY',
          'No native runner for this device',
        );
      }
      final port = (entry as Map)['port'];
      final token = entry['token'];
      if (port is! int ||
          port < 1 ||
          port > 65535 ||
          token is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token)) {
        throw const FormatException();
      }
      // Fixed IPv4 loopback: configuration cannot redirect credentials remotely.
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: remaining(),
      );
      socket.add(
        utf8.encode(
          '${jsonEncode({'version': 1, 'platform': platform, 'device': device, 'token': token, 'deadline': deadline.millisecondsSinceEpoch, ...command})}\n',
        ),
      );
      await socket.flush().timeout(remaining());
      var bytes = 0;
      final line = await socket
          .map<List<int>>((chunk) {
            bytes += chunk.length;
            if (bytes > 8 * 1024 * 1024) throw const FormatException();
            return chunk;
          })
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(remaining());
      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['version'] != 1 ||
          response['platform'] != platform ||
          response['device'] != device) {
        throw const FormatException();
      }
      if (response['ok'] != true) {
        // Never reflect runner diagnostics: they may contain visible UI text.
        final code = response['code'];
        throw PlatformException(
          [
                'TIMEOUT',
                'INVALID_ARGUMENT',
                'UNSUPPORTED_CAPABILITY',
              ].contains(code)
              ? code as String
              : 'BACKEND_ERROR',
          'Native runner rejected or failed the operation',
        );
      }
      return response;
    } on PlatformException {
      rethrow;
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'Native runner deadline exceeded',
      );
    } on SocketException {
      throw const PlatformException(
        'IO_ERROR',
        'Native runner connection failed',
      );
    } on FileSystemException {
      throw const PlatformException(
        'IO_ERROR',
        'Cannot read native runner configuration',
      );
    } catch (_) {
      throw const PlatformException(
        'BACKEND_ERROR',
        'Invalid native runner configuration or response',
      );
    } finally {
      socket?.destroy();
    }
  }
}
