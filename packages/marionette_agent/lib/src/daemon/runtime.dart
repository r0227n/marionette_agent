import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import 'dart:io';

import '../protocol/protocol.dart';

/// User-specific IPC directory with 0700 permissions. Validate owner and type even for predictable paths.
class RuntimeDirectory {
  RuntimeDirectory(this.path);
  final String path;
  String get socket => p.join(path, 's');
  String get metadata => p.join(path, 'daemon.json');
  static Future<RuntimeDirectory> prepare({String? directory}) async {
    final id = await Process.run('/usr/bin/id', ['-u']);
    if (id.exitCode != 0) {
      throw const AgentError('IO_ERROR', 'Cannot determine runtime owner');
    }
    final uid = (id.stdout as String).trim();
    final path =
        directory ??
        Platform.environment['MARIONETTE_AGENT_RUNTIME_DIR'] ??
        '/tmp/mra-$uid';
    if (!p.isAbsolute(path) || utf8.encode(path).length > 80) {
      throw const AgentError(
        'IO_ERROR',
        'Runtime directory must be absolute and at most 80 bytes',
      );
    }
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      final create = await Process.run('/bin/mkdir', ['-m', '700', path]);
      if (create.exitCode != 0 && !Directory(path).existsSync()) {
        throw const AgentError('IO_ERROR', 'Cannot create runtime directory');
      }
    }
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const AgentError('IO_ERROR', 'Unsafe runtime directory');
    }
    final stat = await Process.run(
      '/usr/bin/stat',
      Platform.isMacOS ? ['-f', '%u:%Lp', path] : ['-c', '%u:%a', path],
    );
    if (stat.exitCode != 0 || (stat.stdout as String).trim() != '$uid:700') {
      throw const AgentError(
        'IO_ERROR',
        'Runtime directory must be owned by this user with mode 0700',
      );
    }
    return RuntimeDirectory(path);
  }

  Future<void> privateFile(String file) async {
    final result = await Process.run('/bin/chmod', ['600', file]);
    if (result.exitCode != 0) {
      throw const AgentError('IO_ERROR', 'Cannot secure runtime file');
    }
  }

  /// Acquire OS lock within deadline. Caller performs release and close in finally.
  Future<RandomAccessFile> lock(String name, DateTime deadline) async {
    final file = File(p.join(path, name));
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const AgentError('IO_ERROR', 'Unsafe lock file');
    }
    final handle = await file.open(mode: FileMode.append);
    try {
      await privateFile(file.path);
      while (DateTime.now().isBefore(deadline)) {
        try {
          await handle.lock(FileLock.exclusive);
          return handle;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      throw const AgentError('TIMEOUT', 'Daemon lock deadline exceeded');
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }
}
