import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform_exception.dart';

Duration remaining(DateTime deadline) {
  final value = deadline.difference(DateTime.now());
  if (value <= Duration.zero) throw TimeoutException('Application deadline');
  return value;
}

/// Owns only a process started here. Output is bounded and never forwarded to
/// CLI diagnostics (Flutter logs include authentication URIs and app inputs).
class OwnedProcess {
  OwnedProcess._(this.process, this.label) {
    _stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) {
            output = _tail(output + chunk);
            _pending = _tail(_pending + chunk);
            final lines = _pending.split('\n');
            _pending = lines.removeLast();
            for (final line in lines) {
              try {
                final events = jsonDecode(line);
                if (events is List) {
                  for (final e in events) {
                    if (e is Map &&
                        e['event'] == 'app.start' &&
                        e['params'] is Map) {
                      appId = e['params']['appId'] as String?;
                    } else if (e is Map &&
                        e['event'] == 'app.started' &&
                        e['params'] is Map &&
                        appId != null &&
                        e['params']['appId'] == appId) {
                      appStarted = true;
                    }
                  }
                }
              } catch (_) {}
            }
          },
          onError: (Object _) {},
          onDone: () => _outputDone.complete(),
        );
    _stderr = process.stderr.listen((_) {}, onError: (Object _) {});
    exited = process.exitCode.then((code) {
      exitCode = code;
      return code;
    });
  }
  final _outputDone = Completer<void>();
  final Process process;
  final String label;
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<List<int>> _stderr;
  late final Future<int> exited;
  int? exitCode;
  String output = '', _pending = '';
  String? appId;
  bool appStarted = false;
  Future<void>? _stopping;
  bool get running => exitCode == null;
  static String _tail(String value) =>
      value.length > 262144 ? value.substring(value.length - 262144) : value;

  static Future<OwnedProcess> start(
    String executable,
    List<String> args, {
    required String label,
    required DateTime deadline,
    String? cwd,
    Map<String, String>? environment,
  }) async {
    remaining(deadline);
    var expired = false;
    final starting = Process.start(
      executable,
      args,
      workingDirectory: cwd,
      environment: environment,
    );
    unawaited(
      starting
          .then((p) async {
            if (expired) await OwnedProcess._(p, label).stop();
          }, onError: (Object _) {})
          .catchError((Object _) {}),
    );
    try {
      final p = await starting.timeout(remaining(deadline));
      return OwnedProcess._(p, label);
    } on ProcessException {
      throw PlatformException(
        'UNSUPPORTED_CAPABILITY',
        '$label is unavailable',
        hint: 'Install the required SDK/tool and make it available on PATH.',
      );
    } on TimeoutException {
      expired = true;
      rethrow;
    }
  }

  Future<String> result(DateTime deadline) async {
    try {
      final code = await exited.timeout(remaining(deadline));
      // Drain the owned process's output before interpreting a short command.
      await _outputDone.future.timeout(remaining(deadline));
      if (code != 0) {
        throw PlatformException(
          'IO_ERROR',
          '$label failed',
          hint:
              'Check SDK setup, project dependencies and available disk space.',
        );
      }
      return output.trim();
    } finally {
      await stop();
    }
  }

  Future<void> stop() => _stopping ??= _stop();
  Future<bool> _wait(int seconds) async {
    try {
      await exited.timeout(Duration(seconds: seconds));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> _stop() async {
    try {
      if (running) {
        if (appId != null) {
          try {
            process.stdin.writeln(
              jsonEncode([
                {
                  'id': 1,
                  'method': 'app.stop',
                  'params': {'appId': appId},
                },
              ]),
            );
            await process.stdin.flush().timeout(const Duration(seconds: 1));
          } catch (_) {}
        } else {
          process.kill(ProcessSignal.sigint);
        }
        if (!await _wait(8)) {
          process.kill(ProcessSignal.sigterm);
          if (!await _wait(3)) {
            // Children still parented by this live process are ours. Never use
            // a name-wide kill (shared Flutter/adb/Simulator processes exist).
            await _killChildren();
            process.kill(ProcessSignal.sigkill);
            if (!await _wait(3)) {
              throw const PlatformException(
                'TIMEOUT',
                'Application process did not exit',
              );
            }
          }
        }
      }
    } finally {
      await _stdout.cancel();
      await _stderr.cancel();
      unawaited(process.stdin.close().catchError((Object _) {}));
      output = '';
      _pending = '';
    }
  }

  Future<void> _killChildren() async {
    if (!running || Platform.isWindows) return;
    try {
      final ps = await Process.run('/bin/ps', [
        '-axo',
        'pid=,ppid=',
      ]).timeout(const Duration(seconds: 2));
      if (!running || ps.exitCode != 0) return;
      final parents = <int, int>{};
      for (final line in (ps.stdout as String).split('\n')) {
        final values = line.trim().split(RegExp(r'\s+'));
        if (values.length == 2) {
          parents[int.parse(values[0])] = int.parse(values[1]);
        }
      }
      final owned = <int>{process.pid};
      for (var changed = true; changed;) {
        changed = false;
        for (final e in parents.entries) {
          if (owned.contains(e.value) && owned.add(e.key)) changed = true;
        }
      }
      for (final child in owned.toList().reversed.where(
        (id) => id != process.pid,
      )) {
        Process.killPid(child, ProcessSignal.sigkill);
      }
    } catch (_) {}
  }
}
