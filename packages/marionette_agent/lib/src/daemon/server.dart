import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../protocol/protocol.dart';
import '../diagnostics/diagnostic_logging.dart';
import '../session/session_manager.dart';
import 'runtime.dart';
import '../workflow/model.dart';

/// JSON line-delimited server with daemon lifetime protected by an OS lock.
class DaemonServer {
  DaemonServer(this.runtime, this.manager);
  final RuntimeDirectory runtime;
  final SessionManager manager;
  final _clients = <Socket>{};
  final _done = Completer<void>();
  ServerSocket? _server;
  RandomAccessFile? _lock;
  Timer? _timer;
  Future<void>? _closeFuture;
  bool _closing = false;
  bool _probing = false;
  final instance =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  /// Expose socket and startup metadata; deliver the final session close response and exit.
  Future<void> run() async {
    _lock = await runtime.lock(
      'daemon.lock',
      DateTime.now().add(const Duration(seconds: 10)),
    );
    try {
      final type = FileSystemEntity.typeSync(
        runtime.socket,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound) {
        // Lifetime OS lock proves no cooperating daemon owns this socket.
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.directory) {
          throw const AgentError('IO_ERROR', 'Unsafe socket path');
        }
        await File(runtime.socket).delete();
      }
      _server = await ServerSocket.bind(
        InternetAddress(runtime.socket, type: InternetAddressType.unix),
        0,
      );
      await runtime.privateFile(runtime.socket);
      final metaType = FileSystemEntity.typeSync(
        runtime.metadata,
        followLinks: false,
      );
      if (metaType == FileSystemEntityType.link ||
          metaType == FileSystemEntityType.directory) {
        throw const AgentError('IO_ERROR', 'Unsafe metadata path');
      }
      await File(runtime.metadata).writeAsString(
        jsonEncode({
          'pid': pid,
          'protocolVersion': protocolVersion,
          'instance': instance,
        }),
      );
      await runtime.privateFile(runtime.metadata);
      manager.onEmpty = () {
        unawaited(close());
      };
      _server!.listen(
        (client) {
          unawaited(_serve(client));
        },
        onError: (Object _) {
          unawaited(close());
        },
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (_probing || _closing) return;
        _probing = true;
        try {
          await manager.probe();
        } finally {
          _probing = false;
        }
      });
      await _done.future;
    } finally {
      await close();
      await _lock?.unlock();
      await _lock?.close();
    }
  }

  Future<void> _serve(Socket client) async {
    _clients.add(client);
    String? requestId;
    Request? receivedRequest;
    try {
      client.add(
        encodeFrame({
          'protocolVersion': protocolVersion,
          'instance': instance,
          'ready': !_closing,
        }),
      );
      final json = await decodeFrames(client).first
          .timeout(const Duration(seconds: 30));
      requestId = json['requestId'] is String
          ? json['requestId'] as String
          : null;
      final request = Request.fromJson(json);
      receivedRequest = request;
      final diagnostics = <DiagnosticEntry>[];
      final response = await captureDiagnostics(
        diagnostics,
        () => manager.handle(request),
      );
      client.add(
        encodeFrame({
          'requestId': request.requestId,
          'diagnostics': diagnostics.map((entry) => entry.toJson()).toList(),
          ...response.toJson(),
        }),
      );
      await client.flush();
    } catch (error) {
      try {
        var safe = error is AgentError
            ? error
            : const AgentError('IO_ERROR', 'IPC request failed');
        final request = receivedRequest;
        if (request?.command == 'workflow') {
          // The execution response was not deliverable. Do not imply that UI
          // actions were never sent or reconstruct progress from a failed frame.
          safe = workflowError(
            safe.withOutcome(Outcome.unknown),
            name: workflowNameFrom(request!.params['workflow']),
            known: false,
          );
        }
        client.add(
          encodeFrame({
            'requestId': requestId,
            ...Result.failure(request?.session, safe).toJson(),
          }),
        );
        await client.flush();
      } catch (_) {
        /* Client may have already timed out. Never retry dispatch. */
      }
    } finally {
      await client.close();
      _clients.remove(client);
      if (_closing && _clients.isEmpty && !_done.isCompleted) _done.complete();
    }
  }

  /// Share the cleanup future and wait for file deletion completion even on re-entry.
  /// Even after final response completes _done, run's finally waits on this future
  /// before releasing lifetime lock, so it does not delete the next daemon socket.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    _timer?.cancel();
    await _server?.close();
    await manager.dispose();
    // Do not tear down the socket that is delivering the final close response.
    for (final path in [runtime.socket, runtime.metadata]) {
      try {
        await File(path).delete();
      } on FileSystemException {
        /* Already absent. */
      }
    }
    if (_clients.isEmpty && !_done.isCompleted) _done.complete();
  }
}
