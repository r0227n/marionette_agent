import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/src/cli/batch_loader.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:test/test.dart';

void main() {
  test(
    'batch entries inherit options without revalidating overridden environment',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mra-batch-options-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/batch.json';
      await File(path).writeAsString('[["snapshot"],["wait","0"]]');
      final parser = CliParser(
        environment: {
          'MARIONETTE_AGENT_SESSION': '',
          'MARIONETTE_AGENT_TIMEOUT_MS': 'invalid',
        },
      );
      parser.parse(['--session', 'valid', '--timeout', '5000', 'batch', path]);
      final batch = await loadBatch(
        path,
        DateTime.now().add(const Duration(seconds: 5)),
        parser,
      );
      expect((batch['steps'] as List).length, 2);
    },
  );
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
