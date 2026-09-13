import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../commands/batch.dart';
import '../protocol/protocol.dart';
import 'common_options.dart';
import 'input_file.dart';
import 'parser.dart';

Future<Json> loadBatch(String path, DateTime deadline, CliParser parser) async {
  Object? decoded;
  try {
    final bytes = path == '-'
        ? await _readStdin(deadline)
        : await readInputFile(path, deadline);
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
    CommonOptions.rejectDuplicateOptions(parser.parser, argv);
    final command = parsed.command;
    if (parsed.rest.isNotEmpty ||
        command == null ||
        !batchCommands.contains(command.name)) {
      invalid('Batch command is not supported');
    }
    steps.add({
      'command': command.name,
      'params': parser.definitions[command.name]!.decode(command),
    });
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
