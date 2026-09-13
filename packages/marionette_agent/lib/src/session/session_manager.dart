import 'dart:async';

import '../diagnostics/diagnostic_logging.dart';

import '../output/content.dart';
import '../backend/backend.dart';
import '../backend/marionette_backend.dart';
import '../commands/registry.dart';
import '../commands/command_context.dart';
import '../snapshot/snapshot_service.dart';
import '../protocol/protocol.dart';
import 'session.dart';
import '../recording/record_service.dart';
import '../workflow/workflow_runner.dart';
import '../workflow/model.dart';

/// Manages URI ownership and session lifetime. I/O from different sessions can run concurrently.
class SessionManager {
  SessionManager(this.factory, this.commands, {RecordService? recordings})
    : recordings = recordings ?? RecordService();
  final RecordService recordings;
  final BackendFactory factory;
  final CommandRegistry commands;
  final snapshots = SnapshotService();
  final sessions = <String, Session>{};
  final _owners = <String, String>{};
  bool stopping = false;
  void Function()? onEmpty;
  void Function()? onQueueIdle;
  bool get hasPending => sessions.values.any((session) => session.pending != 0);

  Json show(Session session) => {
    'name': session.name,
    'state': session.status,
    'uri': session.uri == null ? null : redactUri(session.uri!),
    'snapshotValid': session.observation != null,
    'connectionGeneration': session.epoch,
  };

  /// Reserve session at intake and execute requests in selected session queue.
  Future<Result> handle(Request request) async {
    final debug = DebugDiagnostics(
      enabled: request.debug,
      requestId: request.requestId,
      session: request.session,
    );
    final independent =
        request.command == 'session' && request.params['action'] == 'list';
    final all = request.command == 'close' && request.params['all'] == true;
    final resultSession = independent || all ? null : request.session;
    try {
      request.checkDeadline();
      if (stopping) {
        throw const AgentError('CONNECTION_LOST', 'Daemon is shutting down');
      }
      if (all) {
        if (request.params.length != 1) invalid();
        return await _closeAll(request);
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
        if (sessions.isEmpty && !stopping) {
          stopping = true;
          onEmpty?.call();
        }
        return Result.success(request.session, {'closed': true});
      }
      if (existing == null &&
          request.command != 'connect' &&
          request.command != 'record') {
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
      debug.emit(DebugStage.sessionQueue);
      var started = false;
      final future = session.queue
          .run(() async {
            started = true;
            debug.emit(DebugStage.commandExecute);
            request.checkDeadline();
            if (stopping) {
              throw const AgentError(
                'CONNECTION_LOST',
                'Daemon is shutting down',
              );
            }
            if (request.command == 'record') return recordings.handle(request);
            Json? recording;
            if (request.command == 'close') {
              if (request.params.isNotEmpty) invalid();
              recording = await recordings.close(request);
            }
            Json data;
            if (request.command == 'workflow') {
              data = await WorkflowExecution(
                request,
                session,
                snapshots,
                commands,
              ).run();
            } else {
              final execution = Execution(request, session);
              data = await execution.bound(() => _execute(execution));
            }
            data = limitContent(data, request.maxOutput, request.outputJson);
            if (request.maxOutput != null) {
              snapshots.retainPublished(session, data);
            }
            return {...data, 'recording': ?recording};
          })
          .whenComplete(() {
            session.pending--;
            if (!hasPending) onQueueIdle?.call();
            // Rejections before URI acquisition are temporary reservations, not active connections.
            // Keep the same queue while requests continue, and retain sessions that actually attempted connect for recovery.
            if ((session.closed || session.uri == null) &&
                session.pending == 0 &&
                !recordings.contains(session.name) &&
                identical(sessions[session.name], session)) {
              sessions.remove(session.name);
              if (sessions.isEmpty && !stopping) {
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
      return Result.failure(
        resultSession,
        request.command == 'workflow' && error.details == null
            ? workflowError(
                error,
                name: workflowNameFrom(request.params['workflow']),
              )
            : error,
      );
    } catch (_) {
      return Result.failure(
        resultSession,
        const AgentError('INTERNAL_ERROR', 'Request failed'),
      );
    }
  }

  /// Intake is synchronous: no later connect or command can reserve a session.
  Future<Result> _closeAll(Request request) async {
    stopping = true;
    final targets = sessions.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final results = await Future.wait(
      targets.map((session) async {
        AgentError? failure;
        try {
          await session.queue.run(() async {}).timeout(request.remaining);
          request.checkDeadline();
          await recordings
              .close(
                Request(
                  requestId: request.requestId,
                  session: session.name,
                  command: 'close',
                  params: {},
                  deadline: request.deadline,
                ),
              )
              .timeout(request.remaining);
        } on TimeoutException {
          failure = const AgentError(
            'TIMEOUT',
            'Close deadline exceeded',
            outcome: Outcome.unknown,
          );
        } on AgentError catch (error) {
          failure = error.code == 'TIMEOUT'
              ? error.withOutcome(Outcome.unknown)
              : error;
        } catch (_) {
          failure = const AgentError(
            'BACKEND_ERROR',
            'Session cleanup failed',
            outcome: Outcome.failed,
          );
        }
        // Retire even on drain failure; running sent operations retain unknown,
        // while queued requests are rejected before dispatch.
        session.interrupt();
        final disposal = session.discard();
        session.closed = true;
        session.uri = null;
        try {
          await disposal.timeout(request.remaining);
        } on TimeoutException {
          failure ??= const AgentError(
            'TIMEOUT',
            'Disconnect deadline exceeded',
            outcome: Outcome.unknown,
          );
        } catch (_) {
          failure ??= const AgentError(
            'BACKEND_ERROR',
            'Disconnect failed',
            outcome: Outcome.failed,
          );
        }
        return failure == null
            ? Result.success(session.name, {'closed': true})
            : Result.failure(session.name, failure);
      }),
    );
    sessions.clear();
    _owners.clear();
    onEmpty?.call();
    final data = <String, Object?>{
      'closed': true,
      'sessions': results.map((result) => result.toJson()).toList(),
    };
    if (results.every((result) => result.error == null)) {
      return Result.success(null, data);
    }
    final unknown = results.any(
      (result) => result.error?.outcome == Outcome.unknown,
    );
    return Result.failure(
      null,
      AgentError(
        results.any((result) => result.error?.code == 'TIMEOUT')
            ? 'TIMEOUT'
            : 'CLOSE_FAILED',
        'Some sessions could not be confirmed closed',
        outcome: unknown ? Outcome.unknown : Outcome.failed,
        details: data,
      ),
    );
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
    await recordings.dispose();
    for (final session in sessions.values) {
      session.discard();
    }
    sessions.clear();
    _owners.clear();
  }
}
