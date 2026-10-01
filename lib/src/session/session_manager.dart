import 'dart:async';

import 'package:marionette_agent_util/marionette_agent_util.dart';

import '../backend/backend.dart';
import '../backend/connection_uri.dart';
import '../commands/batch.dart';
import '../commands/command_context.dart';
import '../commands/registry.dart';
import '../diagnostics/diagnostic_logging.dart';
import '../output/content.dart';
import '../protocol/protocol.dart';
import '../recording/record_service.dart';
import '../snapshot/snapshot_service.dart';
import '../workflow/model.dart';
import '../workflow/workflow_runner.dart';
import 'session.dart';

/// Manages URI ownership and session lifetime. I/O from different sessions can run concurrently.
class SessionManager {
  SessionManager(
    this.factory,
    this.commands, {
    RecordService? recordings,
    ApplicationLauncher? launcher,
  }) : recordings = recordings ?? RecordService(),
       launcher = launcher ?? PlatformApplicationLauncher();
  final RecordService recordings;
  final ApplicationLauncher launcher;
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
    if (session.application != null)
      'application': session.application!.description,
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
    final resultSession = request.resultSession;
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
          request.command != 'launch' &&
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
            final incoming = request;
            started = true;
            debug.emit(DebugStage.commandExecute);
            request.checkDeadline();
            if (stopping) {
              throw const AgentError(
                'CONNECTION_LOST',
                'Daemon is shutting down',
              );
            }
            final authorized = session.actionPolicy.authorize(
              incoming,
              session.epoch,
            );
            return _runAuthorized(authorized, session);
          })
          .whenComplete(() {
            session.pending--;
            if (!hasPending) onQueueIdle?.call();
            if ((session.closed ||
                    (session.uri == null &&
                        !session.actionPolicy.hasPending &&
                        session.application == null)) &&
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

  Future<Json> _runAuthorized(Request request, Session session) async {
    if (request.command == 'launch') return _launch(request, session);
    if (request.command == 'deny') return {'denied': true};
    if (request.command == 'record') {
      return recordings.handle(
        request,
        backend: session.status == 'connected' ? session.backend : null,
        uri: session.status == 'connected' ? session.uri : null,
      );
    }
    if (request.command == 'close') {
      if (request.params.isNotEmpty) invalid();
      final recording = await recordings.close(request);
      await _stopApplication(session);
      // Cleanup may outlive the caller's deadline. Always retire the session
      // after the owned environment has stopped, even if delivery timed out.
      await _disconnectSession(session, request.deadline);
      return {'closed': true, 'recording': ?recording};
    }
    Json data;
    if (request.command == 'batch') {
      data = await executeBatch(request, session, snapshots, commands);
    } else if (request.command == 'workflow') {
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
    return data;
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
        try {
          await _stopApplication(session);
        } on AgentError catch (error) {
          failure ??= error;
        }
        // Retire even on drain failure; running sent operations retain unknown,
        // while queued requests are rejected before dispatch.
        session.interrupt();
        try {
          await _disconnectSession(session, request.deadline);
        } on AgentError catch (error) {
          failure ??= error;
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

  /// Retire ownership immediately, but report success only after disconnect.
  /// Both close forms share deadlines, error classification and ref invalidation.
  Future<void> _disconnectSession(Session session, DateTime deadline) async {
    if (session.uri != null) _owners.remove(session.uri.toString());
    final disposal = session.discard();
    session.uri = null;
    session.closed = true;
    try {
      await disposal.timeout(deadline.difference(DateTime.now()));
    } on TimeoutException {
      throw const AgentError(
        'TIMEOUT',
        'Disconnect deadline exceeded',
        outcome: Outcome.unknown,
      );
    } catch (_) {
      throw const AgentError(
        'BACKEND_ERROR',
        'Disconnect failed',
        outcome: Outcome.failed,
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
        return _connect(context, uri);
      case 'state':
        if (request.params.length != 1 ||
            request.params['action'] != 'export') {
          invalid('Invalid state request');
        }
        context.requireConnected();
        return {'uri': session.uri.toString()};
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

  Future<Json> _connect(Execution context, Uri uri) async {
    final session = context.session;
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
  }

  Future<void> _stopApplication(Session session) async {
    final app = session.application;
    if (app == null) return;
    try {
      await app.stop();
      session.application = null;
    } on PlatformException catch (e) {
      throw AgentError(
        e.code,
        e.message,
        hint: e.hint,
        outcome: Outcome.failed,
      );
    }
  }

  Future<Json> _launch(Request request, Session session) async {
    if (session.uri != null ||
        session.application != null ||
        recordings.contains(session.name)) {
      throw const AgentError(
        'SESSION_CONFLICT',
        'Close the session before launching an application',
      );
    }
    try {
      final options = LaunchOptions.fromJson(request.params);
      final app = await launcher.start(options, request.deadline);
      session.application = app;
      if (stopping || session.closed) {
        throw const AgentError(
          'CONNECTION_LOST',
          'Session closed during launch',
        );
      }
      request.checkDeadline();
      final execution = Execution(request, session);
      final data = await execution.bound(() async {
        await _connect(execution, normalizeUri(app.uri.toString()));
        // A URI file alone is insufficient: verify Marionette is ready to observe.
        await execution.read((backend) => backend.inspect());
        return show(session);
      });
      unawaited(
        app.exited
            .then((_) {
              if (identical(session.application, app)) session.discard();
            })
            .catchError((Object _) {}),
      );
      return data;
    } catch (error) {
      if (session.uri != null) _owners.remove(session.uri.toString());
      session.discard();
      session.uri = null;
      await _stopApplication(session);
      if (error is PlatformException) {
        throw AgentError(error.code, error.message, hint: error.hint);
      }
      rethrow;
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
    try {
      await recordings.dispose();
    } finally {
      try {
        await launcher.dispose();
      } finally {
        for (final session in sessions.values) {
          session.discard();
        }
        sessions.clear();
        _owners.clear();
      }
    }
  }
}
