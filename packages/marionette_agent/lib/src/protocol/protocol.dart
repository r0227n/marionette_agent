import 'dart:convert';

import 'command_scope.dart';

/// IPC compatibility across CLIs. Update independently from public JSON schemaVersion.
const protocolVersion = 7;

/// Default daemon idle lifetime in milliseconds; explicit 0 disables it.
const defaultIdleTimeoutMs = 3600000;

/// Version for result envelopes rendered to stdout.
const schemaVersion = 1;

/// Maximum size of newline-delimited IPC frames, including base64 image payloads.
const maxFrameBytes = 64 * 1024 * 1024;

/// Bounded transport time for an authoritative result after execution expires.
const ipcResponseGrace = Duration(milliseconds: 250);

/// Public CLI version for this package.
const version = '0.0.1';

/// JSON object exchanged by protocol layer; do not carry upstream response types.
typedef Json = Map<String, Object?>;

/// Distinguish pre-dispatch failures, confirmed failures, and indeterminate outcomes for UI actions.
enum Outcome { notSent, failed, unknown }

/// Secret-safe errors that are the source of truth for classification and exit codes.
class AgentError implements Exception {
  const AgentError(
    this.code,
    this.message, {
    this.hint,
    this.details,
    this.outcome = Outcome.notSent,
  });
  final String code;
  final String message;
  final String? hint;
  final Json? details;
  final Outcome outcome;
  int get exitCode => switch (code) {
    'INVALID_ARGUMENT' => 2,
    'NOT_CONNECTED' || 'SESSION_CONFLICT' || 'CONNECTION_LOST' => 3,
    'TARGET_NOT_FOUND' ||
    'AMBIGUOUS_TARGET' ||
    'STALE_REF' ||
    'UNRESOLVABLE_TARGET' => 4,
    'TIMEOUT' => 5,
    'UNSUPPORTED_CAPABILITY' => 6,
    _ => 1,
  };
  AgentError withOutcome(Outcome value) =>
      AgentError(code, message, hint: hint, outcome: value, details: details);
  Json toJson() => {
    if (details != null) 'details': details,
    'code': code,
    'message': message,
    'hint': hint,
    'outcome': outcome == Outcome.notSent ? 'not_sent' : outcome.name,
  };
  factory AgentError.fromJson(Json json) {
    if (json['code'] is! String ||
        json['message'] is! String ||
        !['not_sent', 'failed', 'unknown'].contains(json['outcome'])) {
      throw const AgentError('IO_ERROR', 'Invalid error response');
    }
    return AgentError(
      json['code'] as String,
      json['message'] as String,
      hint: json['hint'] as String?,
      details: json['details'] == null ? null : asJson(json['details']),
      outcome: switch (json['outcome']) {
        'unknown' => Outcome.unknown,
        'failed' => Outcome.failed,
        _ => Outcome.notSent,
      },
    );
  }
  @override
  String toString() => '$code: $message';
}

/// Return argument errors with unified code and user guidance; do not echo input values.
Never invalid([String message = 'Invalid arguments']) => throw AgentError(
  'INVALID_ARGUMENT',
  message,
  hint: 'Run marionette-agent --help',
);

/// Session-name constraints to avoid uncontrolled strings in paths and socket names.
bool validSession(String name) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(name);

void validateSession(String name) {
  if (!validSession(name)) invalid('Invalid session name');
}

int? outputLimit(Object? value) {
  if (value == null) return null;
  if (value is! int || value <= 0) invalid('Expected a positive integer');
  return value;
}

int positiveInteger(String value) {
  final result = int.tryParse(value);
  if (!RegExp(r'^[0-9]+$').hasMatch(value) || result == null) {
    invalid('Expected a positive integer');
  }
  return outputLimit(result)!;
}

int parseDurationMs(
  String value, {
  bool allowZero = false,
  bool units = false,
}) {
  final match = RegExp(units ? r'^([0-9]+)(ms|s|m|h)?$' : r'^([0-9]+)$')
      .firstMatch(value);
  if (match == null) invalid('Invalid duration');
  final count = BigInt.parse(match.group(1)!);
  final unit = units ? match.group(2) : null;
  final multiplier = switch (unit) {
    's' => 1000,
    'm' => 60000,
    'h' => 3600000,
    _ => 1,
  };
  final ms = count * BigInt.from(multiplier);
  // Duration uses microseconds; DateTime must also represent the deadline.
  if (ms > BigInt.from(9223372036854775) || (!allowZero && ms == BigInt.zero)) {
    invalid('Duration is out of range');
  }
  final result = ms.toInt();
  try {
    DateTime.now().add(Duration(milliseconds: result));
  } on ArgumentError {
    invalid('Duration is out of range');
  }
  return result;
}

/// Public result envelope must hold either success data or error, never both.
class Result {
  Result.success(this.session, this.data) : error = null;
  Result.failure(this.session, this.error) : data = null;
  final String? session;
  final Json? data;
  final AgentError? error;
  int get exitCode => error?.exitCode ?? 0;
  Json toJson() => {
    'schemaVersion': schemaVersion,
    'ok': error == null,
    'session': session,
    'data': data,
    'error': error?.toJson(),
  };
  factory Result.fromJson(Json json) {
    if (json['schemaVersion'] != schemaVersion ||
        json['ok'] is! bool ||
        (json['session'] != null && json['session'] is! String)) {
      throw const AgentError('IO_ERROR', 'Incompatible response schema');
    }
    if (json['ok'] == true && json['error'] == null && json['data'] is Map) {
      return Result.success(json['session'] as String?, asJson(json['data']));
    }
    if (json['ok'] == false && json['data'] == null && json['error'] is Map) {
      return Result.failure(
        json['session'] as String?,
        AgentError.fromJson(asJson(json['error'])),
      );
    }
    throw const AgentError('IO_ERROR', 'Invalid response envelope');
  }
}

/// Validate external JSON as a string-keyed object and enforce strict type boundaries.
Json asJson(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const AgentError('IO_ERROR', 'Expected JSON object');
  }
  return Map<String, Object?>.from(value);
}

/// Single-shot IPC request with absolute deadline, including queue wait time.
class Request {
  Request({
    required this.requestId,
    required this.session,
    required this.command,
    required this.params,
    required this.deadline,
    this.maxOutput,
    this.outputJson = false,
    this.debug = false,
    this.policy,
  });
  final String requestId;
  final String session;
  final String command;
  final Json params;
  final DateTime deadline;
  final int? maxOutput;
  final bool outputJson;
  final bool debug;
  final Json? policy;
  String? get resultSession =>
      usesSession(
        command,
        // IPC workflow requests are always executable; schema/validate stay local.
        action: command == 'workflow' ? 'run' : params['action'],
        all: params['all'] == true,
      )
      ? session
      : null;
  Duration get remaining => deadline.difference(DateTime.now());
  void checkDeadline() {
    if (remaining <= Duration.zero) {
      throw const AgentError('TIMEOUT', 'Request deadline exceeded');
    }
  }

  Json toJson() => {
    'protocolVersion': protocolVersion,
    'requestId': requestId,
    'session': session,
    'command': command,
    'params': params,
    'deadline': deadline.millisecondsSinceEpoch,
    'maxOutput': maxOutput,
    'outputJson': outputJson,
    'debug': debug,
    if (policy != null) 'policy': policy,
  };
  factory Request.fromJson(Json json) {
    if (json['protocolVersion'] != protocolVersion) {
      throw const AgentError(
        'IO_ERROR',
        'Incompatible IPC protocol; close the old daemon first',
      );
    }
    if (json['requestId'] is! String ||
        json['session'] is! String ||
        json['command'] is! String ||
        json['deadline'] is! int) {
      invalid('Invalid IPC request');
    }
    final maxOutput = outputLimit(json['maxOutput']);
    if (json['debug'] != null && json['debug'] is! bool) {
      invalid('Invalid debug policy');
    }
    if (json['outputJson'] != null && json['outputJson'] is! bool) {
      invalid('Invalid output policy');
    }
    final name = json['session'] as String;
    validateSession(name);
    return Request(
      requestId: json['requestId'] as String,
      session: name,
      maxOutput: maxOutput,
      outputJson: json['outputJson'] == true,
      debug: json['debug'] == true,
      policy: json['policy'] == null ? null : asJson(json['policy']),
      command: json['command'] as String,
      params: asJson(json['params']),
      deadline: DateTime.fromMillisecondsSinceEpoch(json['deadline'] as int),
    );
  }
}

/// Convert to newline-delimited UTF-8 JSON and validate size limit before sending.
List<int> encodeFrame(Json json) {
  final bytes = utf8.encode('${jsonEncode(json)}\n');
  if (bytes.length > maxFrameBytes) {
    throw const AgentError('IO_ERROR', 'IPC frame exceeds 64 MiB');
  }
  return bytes;
}

/// Parse JSON using standard UTF-8 decoder and LineSplitter; custom logic is only byte-limit checks.
Stream<Json> decodeFrames(Stream<List<int>> input) async* {
  try {
    final lines = _boundedChunks(input)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      yield asJson(jsonDecode(line));
    }
  } on FormatException {
    throw const AgentError('IO_ERROR', 'Malformed IPC frame');
  }
}

// Check frame byte size before the decoder buffers a large unterminated chunk.
Stream<List<int>> _boundedChunks(Stream<List<int>> input) async* {
  var pending = 0;
  await for (final chunk in input) {
    var start = 0;
    while (start < chunk.length) {
      final newline = chunk.indexOf(10, start);
      final end = newline < 0 ? chunk.length : newline + 1;
      pending += end - start;
      if (pending > maxFrameBytes ||
          (newline < 0 && pending == maxFrameBytes)) {
        throw const AgentError('IO_ERROR', 'IPC frame exceeds 64 MiB');
      }
      if (newline >= 0) pending = 0;
      start = end;
    }
    yield chunk;
  }
  if (pending != 0) throw const AgentError('IO_ERROR', 'Incomplete IPC frame');
}
