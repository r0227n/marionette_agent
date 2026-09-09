import 'dart:async';

import '../backend/backend.dart';
import '../backend/marionette_backend.dart';
import '../commands/registry.dart';
import '../commands/command_context.dart';
import '../snapshot/snapshot_service.dart';
import '../protocol/protocol.dart';
import 'session.dart';

/// Manages URI ownership and session lifetime. I/O from different sessions can run concurrently.
class SessionManager {
  SessionManager(this.factory, this.commands);
  final BackendFactory factory;
  final CommandRegistry commands;
  final snapshots = SnapshotService();
  final sessions = <String, Session>{};
  final _owners = <String, String>{};
  bool stopping = false;
  void Function()? onEmpty;

  Json show(Session session) => {
    'name': session.name,
    'state': session.status,
    'uri': session.uri == null ? null : redactUri(session.uri!),
    'snapshotValid': session.observation != null,
    'connectionGeneration': session.epoch,
  };

  /// Reserve session at intake and execute requests in selected session queue.
  Future<Result> handle(Request request) async {
    final independent =
        request.command == 'session' && request.params['action'] == 'list';
    final resultSession = independent ? null : request.session;
    try {
      request.checkDeadline();
      if (stopping) {
        throw const AgentError('CONNECTION_LOST', 'Daemon is shutting down');
      }
      if (independent) {
        if (request.params.length != 1) invalid();
        // Capture names, then probe through each session's own queue.
        final names = sessions.keys.toList()..sort();
        final results = await Future.wait(
          names.map(
            (name) => handle(
              Request(
                requestId: request.requestId,
                session: name,
                command: 'session',
                params: {'action': 'show'},
                deadline: request.deadline,
              ),
            ),
          ),
        );
        for (final result in results) {
          if (result.error != null && result.error!.code != 'NOT_CONNECTED') {
            throw result.error!;
          }
        }
        return Result.success(null, {
          'sessions': [
            for (final result in results)
              if (result.data != null) result.data!,
          ],
        });
      }
      final existing = sessions[request.session];
      if (existing == null && request.command == 'close') {
        if (request.params.isNotEmpty) invalid();
        if (sessions.isEmpty) {
          stopping = true;
          onEmpty?.call();
        }
        return Result.success(request.session, {'closed': true});
      }
      if (existing == null && request.command != 'connect') {
        throw const AgentError(
          'NOT_CONNECTED',
          'Session is not connected',
          hint: 'Run connect, then snapshot',
        );
      }
      // Reservation is synchronous, before the first await. A pending connect
      // keeps the daemon alive even while the last connected session closes.
      final session = existing ?? Session(request.session);
      sessions[request.session] = session;
      session.pending++;
      var started = false;
      final future = session.queue
          .run(() async {
            started = true;
            request.checkDeadline();
            final execution = Execution(request, session);
            return execution.bound(() => _execute(execution));
          })
          .whenComplete(() {
            session.pending--;
            // Rejections before URI acquisition are temporary reservations, not active connections.
            // Keep the same queue while requests continue, and retain sessions that actually attempted connect for recovery.
            if ((session.closed || session.uri == null) &&
                session.pending == 0 &&
                identical(sessions[session.name], session)) {
              sessions.remove(session.name);
              if (sessions.isEmpty) {
                stopping = true;
                onEmpty?.call();
              }
            }
          });
      try {
        final data = await future.timeout(
          request.remaining,
          onTimeout: () async {
            if (started) return await future;
            throw TimeoutException('queue');
          },
        );
        return Result.success(resultSession, data);
      } on TimeoutException {
        throw const AgentError('TIMEOUT', 'Request expired in queue');
      }
    } on AgentError catch (error) {
      return Result.failure(resultSession, error);
    } catch (_) {
      return Result.failure(
        resultSession,
        const AgentError('INTERNAL_ERROR', 'Request failed'),
      );
    }
  }

  Future<Json> _execute(Execution context) async {
    final request = context.request;
    final session = context.session;
    switch (request.command) {
      case 'connect':
        if (request.params.length != 1 || request.params['uri'] is! String) {
          invalid('Usage: connect <uri>');
        }
        final uri = normalizeUri(request.params['uri'] as String);
        final key = uri.toString();
        if (!session.closed && session.uri != null && session.uri != uri) {
          throw const AgentError(
            'SESSION_CONFLICT',
            'Close the session before changing its URI',
          );
        }
        if (_owners[key] != null && _owners[key] != session.name) {
          throw const AgentError(
            'SESSION_CONFLICT',
            'URI is already owned by another session',
          );
        }
        if (session.status == 'connected') {
          try {
            await context.read((backend) => backend.checkConnection());
            return show(session);
          } on AgentError catch (error) {
            if (error.code != 'CONNECTION_LOST') rethrow;
            // Explicit connect can recover broken connections. UI operations are not sent here.
            session.discard();
            context.epoch = session.epoch;
          }
        }
        _owners[key] = session.name;
        session.uri = uri;
        session.closed = false;
        session.discard();
        context.epoch = session.epoch;
        session.status = 'connecting';
        final backend = factory();
        session.backend = backend;
        try {
          await backend.connect(uri);
          context.check();
          session.status = 'connected';
        } catch (_) {
          // connect can finish after a timeout/disposal. Always dispose again.
          unawaited(backend.disconnect().catchError((Object _) {}));
          if (session.epoch == context.epoch) session.discard();
          rethrow;
        }
        return show(session);
      case 'close':
        if (request.params.isNotEmpty) invalid();
        if (session.uri != null) _owners.remove(session.uri.toString());
        session.discard();
        session.uri = null;
        session.closed = true;
        return {'closed': true};
      case 'session':
        if (request.params.length != 1 || request.params['action'] != 'show') {
          invalid('Usage: session list|show');
        }
        if (session.status == 'connected') {
          try {
            await context.read((backend) => backend.checkConnection());
          } on AgentError catch (error) {
            if (error.code != 'CONNECTION_LOST') rethrow;
            session.discard();
          }
        }
        return show(session);
      default:
        context.requireConnected();
        return commands.dispatch(
          CommandContext(context, snapshots),
          request.command,
          request.params,
        );
    }
  }

  /// Called by daemon timer. Health probes share queues with user commands.
  Future<void> probe() async {
    await Future.wait(
      sessions.values.toList().map((session) async {
        if (session.status != 'connected' || session.pending != 0) return;
        final request = Request(
          requestId: 'health',
          session: session.name,
          command: 'session',
          params: {'action': 'show'},
          deadline: DateTime.now().add(const Duration(seconds: 2)),
        );
        await handle(request);
      }),
    );
  }

  Future<void> dispose() async {
    stopping = true;
    for (final session in sessions.values) {
      session.discard();
    }
    sessions.clear();
    _owners.clear();
  }
}
