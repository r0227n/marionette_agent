import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'platform_exception.dart';

Future<String> readDeviceInventory(
  String executable,
  List<String> arguments,
  DateTime deadline,
) async {
  Process? process;
  try {
    final duration = deadline.difference(DateTime.now());
    if (duration <= Duration.zero) throw TimeoutException('device list');
    final pending = Process.start(executable, arguments);
    try {
      process = await pending.timeout(duration);
    } on TimeoutException {
      unawaited(
        pending.then((value) {
          value.kill(ProcessSignal.sigkill);
        }),
      );
      rethrow;
    }
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    final code = await process.exitCode.timeout(
      deadline.difference(DateTime.now()),
    );
    final text = await output.timeout(deadline.difference(DateTime.now()));
    await errors.timeout(deadline.difference(DateTime.now()));
    if (code != 0) {
      throw const PlatformException('IO_ERROR', 'Cannot enumerate devices');
    }
    return text;
  } on PlatformException {
    rethrow;
  } on TimeoutException {
    throw const PlatformException(
      'TIMEOUT',
      'Device inventory deadline exceeded',
    );
  } catch (_) {
    throw const PlatformException('IO_ERROR', 'Cannot enumerate devices');
  } finally {
    process?.kill(ProcessSignal.sigkill);
  }
}
