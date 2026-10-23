import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform_exception.dart';

typedef NativeProcessRunner = Future<Uint8List> Function(
  String executable,
  List<String> arguments,
  DateTime deadline,
);

/// Short native-tool invocation. Bounds output, discards diagnostics (which can
/// contain screen text), and terminates only the process this invocation owns.
Future<Uint8List> runNativeProcess(
  String executable,
  List<String> arguments,
  DateTime deadline,
) async {
  Process? process;
  StreamSubscription<List<int>>? output, errors;
  var expired = false;
  Duration remaining() {
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) throw TimeoutException('native UI');
    return value;
  }

  try {
    remaining();
    final pending = Process.start(executable, arguments);
    unawaited(
      pending.then((p) {
        if (expired) {
          p.kill(ProcessSignal.sigkill);
          unawaited(p.stdout.drain<void>());
          unawaited(p.stderr.drain<void>());
          unawaited(p.stdin.close());
        }
      }, onError: (Object _) {}),
    );
    process = await pending.timeout(remaining());
    unawaited(process.stdin.close());
    final bytes = BytesBuilder(copy: false);
    final done = Completer<void>();
    var overflow = false;
    output = process.stdout.listen(
      (chunk) {
        if (overflow) return;
        if (bytes.length + chunk.length > 32 * 1024 * 1024) {
          overflow = true;
          process?.kill(ProcessSignal.sigkill);
        } else {
          bytes.add(chunk);
        }
      },
      onDone: done.complete,
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
        overflow = true;
      },
    );
    errors = process.stderr.listen((_) {}, onError: (Object _) {});
    final code = await process.exitCode.timeout(remaining());
    await done.future.timeout(remaining());
    if (code != 0 || overflow) {
      throw const PlatformException(
        'IO_ERROR',
        'Native UI tool failed',
        hint: 'Check the selected device and native tool installation. Observe again before retrying an action.',
      );
    }
    return bytes.takeBytes();
  } on TimeoutException {
    expired = true;
    throw const PlatformException('TIMEOUT', 'Native UI deadline exceeded');
  } on ProcessException {
    throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'Native UI tool is unavailable',
      hint: 'iOS requires idb and idb_companion on PATH; Android requires adb.',
    );
  } finally {
    process?.kill(ProcessSignal.sigkill);
    await output?.cancel();
    await errors?.cancel();
  }
}

String nativeOutput(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    throw const PlatformException('BACKEND_ERROR', 'Invalid native UI output');
  }
}
