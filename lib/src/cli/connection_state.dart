import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../backend/connection_uri.dart';
import '../protocol/protocol.dart';
import 'input_file.dart';
import 'process_runner.dart';

Future<String> loadConnectionState(String path, DateTime deadline) async {
  try {
    return await _loadConnectionState(path, deadline);
  } on TimeoutException {
    throw const AgentError('TIMEOUT', 'State loading deadline exceeded');
  } on FileSystemException {
    throw const AgentError('IO_ERROR', 'Cannot read connection state');
  }
}

Future<String> _loadConnectionState(String path, DateTime deadline) async {
  // Saved connection URIs contain authentication. Require private local files.
  final stat = await runProcessUntil(
    '/usr/bin/stat',
    Platform.isMacOS ? ['-f', '%u:%Lp', path] : ['-c', '%u:%a', path],
    deadline,
  );
  final uid = await runProcessUntil('/usr/bin/id', ['-u'], deadline);
  final expectedOwner = '${uid.stdout}'.trim();
  if (stat.exitCode != 0 ||
      uid.exitCode != 0 ||
      '${stat.stdout}'.trim() != '$expectedOwner:600' ||
      await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw const AgentError(
      'IO_ERROR',
      'State must be an owned regular file with mode 0600',
    );
  }
  final bytes = await readInputFile(path, deadline);
  Object? data;
  try {
    data = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    invalid('Invalid connection state');
  }
  if (data is! Map ||
      data.length != 3 ||
      data['version'] != 1 ||
      data['kind'] != 'connection' ||
      data['uri'] is! String) {
    invalid('Invalid connection state');
  }
  return normalizeUri(data['uri'] as String).toString();
}

Future<Json> saveConnectionState(
  String path,
  Json data,
  DateTime deadline,
) async {
  if (data['uri'] is! String) {
    throw const AgentError('NOT_CONNECTED', 'No connection to save');
  }
  final file = File(path).absolute;
  var created = false;
  try {
    await file.create(exclusive: true);
    created = true;
    final chmod = await runProcessUntil('/bin/chmod', [
      '600',
      file.path,
    ], deadline);
    if (chmod.exitCode != 0) {
      throw const AgentError('IO_ERROR', 'Cannot secure connection state');
    }
    if (!deadline.isAfter(DateTime.now())) {
      throw const AgentError('TIMEOUT', 'State saving deadline exceeded');
    }
    await file.writeAsString(
      jsonEncode({'version': 1, 'kind': 'connection', 'uri': data['uri']}),
      flush: true,
    );
    if (!deadline.isAfter(DateTime.now())) {
      throw const AgentError('TIMEOUT', 'State saving deadline exceeded');
    }
    return {
      'path': file.path,
      'saved': true,
      'scope': 'connection',
      'requiresSnapshot': false,
    };
  } catch (error) {
    if (created) {
      try {
        await file.delete();
      } catch (_) {
        /* Preserve failure. */
      }
    }
    if (error is AgentError) rethrow;
    if (error is TimeoutException) {
      throw const AgentError('TIMEOUT', 'State saving deadline exceeded');
    }
    throw const AgentError(
      'IO_ERROR',
      'Cannot save connection state; use a new path',
    );
  }
}
