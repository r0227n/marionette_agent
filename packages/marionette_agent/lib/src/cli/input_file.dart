import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/protocol.dart';

Future<Uint8List> readInputFile(String path, DateTime deadline) async {
  try {
    final stat = await FileStat.stat(path);
    if (stat.type != FileSystemEntityType.file ||
        stat.size > 32 * 1024 * 1024) {
      invalid('Input file must be a regular file of at most 32 MiB');
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw const AgentError('TIMEOUT', 'Input file deadline exceeded');
    }
    return await File(path).readAsBytes().timeout(remaining);
  } on AgentError {
    rethrow;
  } on TimeoutException {
    throw const AgentError('TIMEOUT', 'Input file deadline exceeded');
  } catch (_) {
    throw const AgentError('IO_ERROR', 'Cannot read input file');
  }
}
