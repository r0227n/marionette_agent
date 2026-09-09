import 'dart:async';
import 'dart:io';

import '../protocol/protocol.dart';
import '../diagnostics/diagnostic_logging.dart';
import 'runtime.dart';

/// Send one request per handshake. Auto-start is only allowed for connect.
class DaemonClient {
  DaemonClient(this.runtime, {List<String>? launchCommand})
    : launchCommand = launchCommand ?? defaultLaunchCommand();
  final RuntimeDirectory runtime;
  final List<String> launchCommand;

  /// Connect both Dart source execution and compiled execution to the same internal daemon mode.
  static List<String> defaultLaunchCommand() {
    final script = Platform.script.toFilePath();
    return script.endsWith('.dart') ||
            script.endsWith('.snapshot') ||
            script.endsWith('.dill')
        ? [Platform.resolvedExecutable, ...Platform.executableArguments, script]
        : [Platform.resolvedExecutable];
  }

  Future<_Connection?> _open(Request request) async {
    Socket? socket;
    try {
      request.checkDeadline();
      socket = await Socket.connect(
        InternetAddress(runtime.socket, type: InternetAddressType.unix),
        0,
        timeout: request.remaining,
      );
      final frames = StreamIterator(decodeFrames(socket));
      if (!await frames.moveNext().timeout(request.remaining)) {
        throw const AgentError('IO_ERROR', 'Missing daemon handshake');
      }
      final hello = frames.current;
      if (hello['protocolVersion'] != protocolVersion) {
        throw const AgentError(
          'IO_ERROR',
          'Incompatible daemon protocol; close the old daemon first',
        );
      }
      if (hello['ready'] != true) {
        socket.destroy();
        return null;
      }
      return _Connection(socket, frames);
    } on SocketException {
      socket?.destroy();
      return null;
    } catch (_) {
      socket?.destroy();
      rethrow;
    }
  }

  /// Include startup wait in the deadline. Never retry after request send even on disconnect.
  Future<Result> send(Request request) async {
    final resultSession =
        request.command == 'session' && request.params['action'] == 'list'
        ? null
        : request.session;
    var sent = false;
    _Connection? connection;
    try {
      connection = await _open(request);
      if (connection == null) {
        if (request.command != 'connect') {
          if (request.command == 'session' &&
              request.params['action'] == 'list') {
            return Result.success(null, {'sessions': []});
          }
          if (request.command == 'close') {
            return Result.success(request.session, {'closed': true});
          }
          throw const AgentError(
            'NOT_CONNECTED',
            'Daemon is not running',
            hint: 'Run connect, then snapshot',
          );
        }
        final lock = await runtime.lock('launch.lock', request.deadline);
        try {
          connection = await _open(request);
          if (connection == null) {
            await Process.start(
              launchCommand.first,
              [...launchCommand.skip(1), '--internal-daemon'],
              mode: ProcessStartMode.detached,
              environment: {'MARIONETTE_AGENT_RUNTIME_DIR': runtime.path},
            );
            while (connection == null) {
              request.checkDeadline();
              await Future<void>.delayed(const Duration(milliseconds: 25));
              connection = await _open(request);
            }
          }
        } finally {
          await lock.unlock();
          await lock.close();
        }
      }
      request.checkDeadline();
      final bytes = encodeFrame(request.toJson());
      sent = true;
      connection.socket.add(bytes);
      await connection.socket.flush().timeout(request.remaining);
      // Small transport grace lets the daemon return its authoritative timeout
      // outcome and retire the backend before the client closes its socket.
      if (!await connection.frames.moveNext().timeout(
        request.remaining + const Duration(milliseconds: 250),
      )) {
        throw const AgentError('CONNECTION_LOST', 'Daemon disconnected');
      }
      final json = connection.frames.current;
      if (json['requestId'] != request.requestId) {
        throw const AgentError('IO_ERROR', 'Mismatched response ID');
      }
      replayDiagnostics(json['diagnostics']);
      return Result.fromJson(json);
    } on TimeoutException {
      return Result.failure(
        resultSession,
        AgentError(
          'TIMEOUT',
          'IPC deadline exceeded',
          outcome: sent ? Outcome.unknown : Outcome.notSent,
        ),
      );
    } on AgentError catch (error) {
      return Result.failure(
        resultSession,
        sent ? error.withOutcome(Outcome.unknown) : error,
      );
    } catch (_) {
      return Result.failure(
        resultSession,
        AgentError(
          'IO_ERROR',
          'Local IPC failed',
          outcome: sent ? Outcome.unknown : Outcome.notSent,
        ),
      );
    } finally {
      connection?.socket.destroy();
      await connection?.frames.cancel();
    }
  }
}

class _Connection {
  _Connection(this.socket, this.frames);
  final Socket socket;
  final StreamIterator<Json> frames;
}
