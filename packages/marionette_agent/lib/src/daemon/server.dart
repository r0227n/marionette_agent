import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:marionette_agent_util/marionette_agent_util.dart';

import '../cli/common_options.dart';
import '../protocol/protocol.dart';
import '../diagnostics/diagnostic_logging.dart';
import '../session/session_manager.dart';
import 'runtime.dart';
import '../workflow/model.dart';

/// JSON line-delimited server with daemon lifetime protected by an OS lock.
class DaemonServer {
  DaemonServer(
    this.runtime,
    this.manager, {
    this.idleTimeoutMs = CommonOptions.defaultIdleTimeoutMs,
  });
  final int idleTimeoutMs;
  Timer? _idleTimer;
  DateTime? _idleDeadline;
  final RuntimeDirectory runtime;
  final SessionManager manager;
  final _clients = <Socket>{};
  final _done = Completer<void>();
  ServerSocket? _server;
  RandomAccessFile? _lock;
  Timer? _timer;
  StreamSubscription<void>? _termination;
  Timer? _shutdownTimer;
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
          'idleTimeoutMs': idleTimeoutMs,
        }),
      );
      await runtime.privateFile(runtime.metadata);
      manager.onQueueIdle = () {
        // Probes must not renew an existing user inactivity interval. They can
        // finish draining the queue after the last client has disconnected.
        if (_idleTimer?.isActive != true) _armIdle();
      };
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
      _armIdle();
      _termination = terminationRequests().listen((_) => unawaited(close()));
      await _done.future;
    } finally {
      await close();
      await _lock?.unlock();
      await _lock?.close();
    }
  }

  Future<void> _serve(Socket client) async {
    _idleTimer?.cancel();
    _clients.add(client);
    var expired = false;
    var responseStarted = false;
    void expire() {
      expired = true;
      client.destroy();
    }

    var expiry = Timer(const Duration(seconds: 30), expire);
    String? requestId;
    Request? receivedRequest;
    var dispatched = false;
    try {
      client.add(
        encodeFrame({
          'protocolVersion': protocolVersion,
          'instance': instance,
          'idleTimeoutMs': idleTimeoutMs,
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
      expiry.cancel();
      expiry = Timer(request.remaining + ipcResponseGrace, expire);
      final diagnostics = <DiagnosticEntry>[];
      dispatched = true;
      _idleDeadline = null;
      final response = await captureDiagnostics(
        diagnostics,
        () => manager.handle(request),
      );
      final frame = encodeFrame({
        'requestId': request.requestId,
        'diagnostics': diagnostics.map((entry) => entry.toJson()).toList(),
        ...response.toJson(),
      });
      responseStarted = true;
      client.add(frame);
      await client.flush();
    } catch (error) {
      // After sending starts, another frame cannot repair a partial response.
      if (responseStarted || expired || _closing) return;
      try {
        var safe = error is AgentError
            ? error
            : const AgentError('IO_ERROR', 'IPC request failed');
        if (dispatched) safe = safe.withOutcome(Outcome.unknown);
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
      try {
        await client.close().timeout(ipcResponseGrace);
      } catch (_) {
        // A stalled or disconnected receiver must not retain the lifetime lock.
      } finally {
        expiry.cancel();
        client.destroy();
        _clients.remove(client);
        _armIdle();
        _finishIfClosed();
      }
    }
  }

  void _armIdle() {
    _idleTimer?.cancel();
    if (_closing ||
        idleTimeoutMs == 0 ||
        _clients.isNotEmpty ||
        manager.hasPending) {
      return;
    }
    // Handshake-only clients suspend the timer while connected, but do not
    // renew the user's inactivity interval. Only dispatched requests renew it.
    _idleDeadline ??= DateTime.now().add(Duration(milliseconds: idleTimeoutMs));
    final remaining = _idleDeadline!.difference(DateTime.now());
    _idleTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _expireIdle,
    );
  }

  void _expireIdle() {
    if (_closing || _clients.isNotEmpty) return;
    if (manager.hasPending || _probing) {
      _idleTimer = Timer(const Duration(milliseconds: 10), _expireIdle);
      return;
    }
    unawaited(close());
  }

  /// Share the cleanup future and wait for file deletion completion even on re-entry.
  /// Even after final response completes _done, run's finally waits on this future
  /// before releasing lifetime lock, so it does not delete the next daemon socket.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    _timer?.cancel();
    _idleTimer?.cancel();
    await _termination?.cancel();
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
    if (_clients.isNotEmpty) {
      _shutdownTimer = Timer(ipcResponseGrace, () {
        for (final client in _clients.toList()) {
          client.destroy();
        }
      });
    }
    _finishIfClosed();
  }

  void _finishIfClosed() {
    if (_closing && _clients.isEmpty) {
      _shutdownTimer?.cancel();
      if (!_done.isCompleted) _done.complete();
    }
  }
}
