import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'batch cancels stalled stdin and exits by its deadline without a daemon',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mra-batch-input-',
      );
      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          'bin/marionette_agent.dart',
          '--json',
          '--timeout',
          '50',
          'batch',
          '-',
        ],
        environment: {
          'MARIONETTE_AGENT_RUNTIME_DIR': '${directory.path}/runtime',
        },
      );
      final output = utf8.decoder.bind(process.stdout).join();
      final errors = utf8.decoder.bind(process.stderr).join();
      try {
        // Keep the pipe open: EOF must not be necessary for deadline cancellation.
        expect(await process.exitCode.timeout(const Duration(seconds: 20)), 5);
        final result = jsonDecode(await output) as Map;
        expect((result['error'] as Map)['code'], 'TIMEOUT');
        expect(await errors, isEmpty);
        expect(Directory('${directory.path}/runtime').existsSync(), false);
      } finally {
        process.kill();
        await process.stdin.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
