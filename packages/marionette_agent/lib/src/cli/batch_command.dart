import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../commands/batch.dart';
import '../protocol/protocol.dart';
import 'parser.dart';
import 'diff_command.dart';

CliCommand batchCommand() => CliCommand(ArgParser(), (args) {
  if (args.rest.length != 1 || args.rest.single.isEmpty) {
    invalid('Usage: batch <JSON-file|->');
  }
  return {'path': args.rest.single};
});

Future<Json> loadBatch(String path, DateTime deadline, CliParser parser) async {
  Object? decoded;
  try {
    final bytes = path == '-'
        ? await _readStdin(deadline)
        : await readBaseline(path, deadline);
    decoded = jsonDecode(utf8.decode(bytes));
  } on AgentError {
    rethrow;
  } on TimeoutException {
    throw const AgentError('TIMEOUT', 'Batch loading deadline exceeded');
  } catch (_) {
    invalid('Cannot read a JSON batch');
  }
  if (decoded is! List || decoded.isEmpty || decoded.length > 100) {
    invalid('Batch requires 1 to 100 argv arrays');
  }
  final steps = <Json>[];
  for (final raw in decoded) {
    if (raw is! List || raw.isEmpty || raw.any((part) => part is! String)) {
      invalid('Batch commands must be argv arrays');
    }
    final argv = raw.cast<String>();
    final ArgResults parsed;
    try {
      parsed = parser.parser.parse(argv);
    } on FormatException {
      invalid('Invalid batch command syntax');
    }
    if (parsed.options.any((name) => parsed.wasParsed(name))) {
      invalid('Batch entries inherit common options; put them on batch itself');
    }
    final invocation = parser.parse(argv);
    if (!batchCommands.contains(invocation.command)) {
      invalid('Batch command is not supported');
    }
    steps.add({'command': invocation.command, 'params': invocation.params});
  }
  return {'steps': steps};
}

Future<List<int>> _readStdin(DateTime deadline) async {
  if (stdin.hasTerminal) invalid('stdin must be redirected');
  final chunks = StreamIterator(stdin);
  final bytes = <int>[];
  try {
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) throw TimeoutException('Batch input');
      if (!await chunks.moveNext().timeout(remaining)) break;
      final chunk = chunks.current;
      if (bytes.length + chunk.length > 1024 * 1024) {
        invalid('Batch exceeds 1 MiB');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    await chunks.cancel();
  }
}
