import 'dart:async';
import 'dart:io';

import '../cli/common_options.dart';
import '../protocol/protocol.dart';
import '../diagnostics/diagnostic_logging.dart';
import 'runtime.dart';
import '../workflow/model.dart';

/// Send one request per handshake. Auto-start is allowed for connect and record start.
class DaemonClient {
  DaemonClient(this.runtime, {List<String>? launchCommand, this.idleTimeoutMs})
    : launchCommand = launchCommand ?? defaultLaunchCommand();
  final RuntimeDirectory runtime;
  final int? idleTimeoutMs;
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
          'Incompatible daemon protocol; use the old CLI to close sessions, then reconnect',
        );
      }
      if (hello['ready'] != true) {
        socket.destroy();
        return null;
      }
      if (idleTimeoutMs != null && hello['idleTimeoutMs'] != idleTimeoutMs) {
        invalid(
          'Idle timeout differs from the running daemon; close its sessions before changing it',
        );
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
    final diagnostics = DebugDiagnostics(
      enabled: request.debug,
      requestId: request.requestId,
      session: request.session,
    );
    final resultSession =
        ((request.command == 'session' && request.params['action'] == 'list') ||
            (request.command == 'close' && request.params['all'] == true))
        ? null
        : request.session;
    var sent = false;
    AgentError deliveryError(AgentError error) {
      if (request.command != 'workflow') {
        return sent ? error.withOutcome(Outcome.unknown) : error;
      }
      final doc = request.params['workflow'];
      return workflowError(
        AgentError(
          sent && error.code != 'TIMEOUT' ? 'IO_ERROR' : error.code,
          error.message,
          hint: error.hint,
          outcome: sent ? Outcome.unknown : Outcome.notSent,
        ),
        name: workflowNameFrom(doc),
        known: !sent,
      );
    }

    _Connection? connection;
    try {
      diagnostics.emit(DebugStage.daemonOpen);
      connection = await _open(request);
      if (connection == null) {
        final startsRecording =
            request.command == 'record' && request.params['action'] == 'start';
        if (request.command != 'connect' && !startsRecording) {
          if (request.command == 'record' &&
              request.params.length == 1 &&
              ['status', 'stop'].contains(request.params['action'])) {
            return Result.success(request.session, {'recordingState': 'idle'});
          }
          if (request.command == 'session' &&
              request.params['action'] == 'list') {
            return Result.success(null, {'sessions': []});
          }
          if (request.command == 'close') {
            return request.params['all'] == true
                ? Result.success(null, {'closed': true, 'sessions': []})
                : Result.success(request.session, {'closed': true});
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
            diagnostics.emit(DebugStage.daemonStart);
            await Process.start(
              launchCommand.first,
              [
                ...launchCommand.skip(1),
                '--internal-daemon',
                '${idleTimeoutMs ?? CommonOptions.defaultIdleTimeoutMs}',
              ],
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
      diagnostics.emit(DebugStage.daemonReady);
      request.checkDeadline();
      final bytes = encodeFrame(request.toJson());
      diagnostics.emit(DebugStage.requestSend);
      sent = true;
      connection.socket.add(bytes);
      await connection.socket.flush().timeout(request.remaining);
      // Small transport grace lets the daemon return its authoritative timeout
      // outcome and retire the backend before the client closes its socket.
      if (!await connection.frames.moveNext().timeout(
        request.remaining + ipcResponseGrace,
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
        deliveryError(
          AgentError(
            'TIMEOUT',
            'IPC deadline exceeded',
            outcome: sent ? Outcome.unknown : Outcome.notSent,
          ),
        ),
      );
    } on AgentError catch (error) {
      return Result.failure(resultSession, deliveryError(error));
    } catch (_) {
      return Result.failure(
        resultSession,
        deliveryError(
          AgentError(
            'IO_ERROR',
            'Local IPC failed',
            outcome: sent ? Outcome.unknown : Outcome.notSent,
          ),
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
