import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:marionette_agent_android/marionette_agent_android.dart';

/// Prepares a private pairing for the separately run Android Studio test agent.
Future<void> main(List<String> args) async {
  if (args.length == 2 && args.first == 'stop') {
    await const AndroidScreenCapturer().stopAgent(
      args[1],
      DateTime.now().add(const Duration(seconds: 10)),
    );
    return;
  }
  if (args.length != 4 || args.first != 'prepare') {
    stderr.writeln(
      'Usage: dart run tool/android_capture.dart prepare <file> <device-name> <port> | stop <file>',
    );
    exitCode = 2;
    return;
  }
  final port = int.tryParse(args[3]);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(args[2]) ||
      port == null ||
      port < 1024 ||
      port > 65535) {
    stderr.writeln('Invalid device name or port');
    exitCode = 2;
    return;
  }
  final file = File(args[1]);
  await file.create(exclusive: true);
  try {
    // Create private before writing the capability; never print the token.
    final permission = await Process.run('chmod', ['600', file.path]);
    if (permission.exitCode != 0) {
      throw const FileSystemException('Cannot secure pairing file');
    }
    final random = Random.secure();
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'device': args[2],
        'port': port,
        'token': List.generate(
          32,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      }),
    );
    stdout.writeln(file.absolute.path);
  } catch (_) {
    await file.delete();
    rethrow;
  }
}
