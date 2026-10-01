import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

final _uriPattern = RegExp(r'\b(?:https?|wss?)://[^\s]+', caseSensitive: false);
final _collectorKey = Object();

enum DebugStage {
  cliParsed,
  runtimePrepare,
  daemonOpen,
  daemonStart,
  daemonReady,
  requestSend,
  daemonDispatch,
  sessionQueue,
  commandExecute,
  daemonResult,
  cliResult,
}

/// Only metadata is accepted: never pass command parameters or error messages.
class DebugDiagnostics {
  DebugDiagnostics({
    required this.enabled,
    required this.requestId,
    required this.session,
    Stopwatch? elapsed,
  }) : _elapsed = elapsed ?? (Stopwatch()..start());
  final bool enabled;
  final String requestId;
  final String? session;
  final Stopwatch _elapsed;

  void emit(DebugStage stage, {String? code}) {
    if (!enabled) return;
    String label(String? value) =>
        value != null &&
            RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)
        ? value
        : 'none';
    const codes = {
      'OK',
      'INVALID_ARGUMENT',
      'NOT_CONNECTED',
      'SESSION_CONFLICT',
      'CONNECTION_LOST',
      'CLOSE_FAILED',
      'TARGET_NOT_FOUND',
      'AMBIGUOUS_TARGET',
      'STALE_REF',
      'UNRESOLVABLE_TARGET',
      'TIMEOUT',
      'UNSUPPORTED_CAPABILITY',
      'IO_ERROR',
      'INTERNAL_ERROR',
      'BACKEND_ERROR',
    };
    Logger('marionette_agent.debug').info(
      'requestId=${label(requestId)} session=${label(session)} '
      'stage=${stage.name} elapsedMs=${_elapsed.elapsedMilliseconds}'
      '${code == null ? '' : ' code=${codes.contains(code) ? code : 'INTERNAL_ERROR'}'}',
    );
  }
}

String _redact(String value) => value
    .replaceAll(_uriPattern, '<redacted-uri>')
    .replaceAll('\r', r'\r')
    .replaceAll('\n', r'\n');

/// A secret-safe diagnostic record that can cross the daemon IPC boundary.
class DiagnosticEntry {
  const DiagnosticEntry(this.level, this.loggerName, this.message);

  final Level level;
  final String loggerName;
  final String message;

  Map<String, Object?> toJson() => {
    'level': level.value,
    'levelName': level.name,
    'loggerName': loggerName,
    'message': message,
  };

  static DiagnosticEntry fromJson(Object? value) {
    if (value is! Map ||
        value['level'] is! int ||
        value['levelName'] is! String ||
        value['loggerName'] is! String ||
        value['message'] is! String) {
      throw const FormatException('Invalid diagnostic record');
    }
    final levelValue = value['level'] as int;
    if (levelValue < Level.INFO.value || levelValue >= Level.OFF.value) {
      throw const FormatException('Invalid diagnostic level');
    }
    return DiagnosticEntry(
      Level(value['levelName'] as String, levelValue),
      value['loggerName'] as String,
      value['message'] as String,
    );
  }

  String format() => '[${level.name}] $loggerName: $message';
}

/// Sends safe package diagnostics to stderr or a request-scoped collector.
///
/// The upstream connector logs authenticated VM Service URIs at INFO and
/// extension arguments (including entered text) below INFO. URI values are
/// therefore redacted, verbose records are suppressed, and attached errors and
/// stack traces are intentionally omitted because their contents are untrusted.
StreamSubscription<LogRecord> configureDiagnosticLogging([
  void Function(String line)? write,
]) {
  Logger.root.level = Level.INFO;
  final output = write ?? stderr.writeln;
  return Logger.root.onRecord.listen((record) {
    final entry = DiagnosticEntry(
      record.level,
      _redact(record.loggerName),
      _redact(record.message),
    );
    final collector = record.zone?[_collectorKey];
    if (collector is _DiagnosticCollector && collector.entries != null) {
      collector.entries!.add(entry);
    } else {
      output(entry.format());
    }
  });
}

/// Associates records emitted by [action] with one daemon request.
Future<T> captureDiagnostics<T>(
  List<DiagnosticEntry> entries,
  Future<T> Function() action,
) async {
  final collector = _DiagnosticCollector(entries);
  try {
    return await runZoned(action, zoneValues: {_collectorKey: collector});
  } finally {
    // Long-lived listeners retain their registration Zone, not this request's
    // completed buffer. Late records take the normal stderr path instead.
    collector.entries = null;
  }
}

class _DiagnosticCollector {
  _DiagnosticCollector(this.entries);
  List<DiagnosticEntry>? entries;
}

/// Re-emits daemon records in the CLI process so its stderr listener prints them.
void replayDiagnostics(Object? value) {
  if (value == null) return;
  if (value is! List) throw const FormatException('Invalid diagnostics');
  for (final raw in value) {
    final entry = DiagnosticEntry.fromJson(raw);
    Logger(entry.loggerName).log(entry.level, entry.message);
  }
}
