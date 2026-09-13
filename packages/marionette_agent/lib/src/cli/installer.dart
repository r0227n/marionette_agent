import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../protocol/protocol.dart';
import 'skill_catalog.dart';

Future<Json> installCli(Json params, String action, DateTime deadline) async {
  Directory? staging;
  Process? process;
  var reserved = false;
  var installed = false;
  String? destination;
  try {
    final source = params['source'] as String?;
    final resolved = source == null
        ? await Isolate.resolvePackageUri(
            Uri.parse('package:marionette_agent/marionette_agent.dart'),
          )
        : null;
    if (source == null && resolved == null) {
      invalid('Compiled CLI installation requires --source');
    }
    final root = p.absolute(
      source ?? p.join(p.dirname(resolved!.toFilePath()), '..'),
    );
    final entry = p.join(root, 'bin', 'marionette_agent.dart');
    if (!File(entry).existsSync() ||
        !File(p.join(root, 'pubspec.yaml'))
            .readAsStringSync()
            .contains('name: marionette_agent\n')) {
      invalid('Source must be the marionette_agent Dart package');
    }
    final directory = p.absolute(params['directory'] as String);
    if (await FileSystemEntity.type(directory, followLinks: false) !=
        FileSystemEntityType.directory) {
      invalid('Installation directory must exist and must not be a symlink');
    }
    destination = p.join(directory, 'marionette-agent');
    final type = await FileSystemEntity.type(destination, followLinks: false);
    if (action == 'install') {
      await File(destination).create(exclusive: true);
      reserved = true;
    } else if (type != FileSystemEntityType.file) {
      invalid('Upgrade requires an existing regular marionette-agent binary');
    }
    staging = await Directory(directory).createTemp('.marionette-agent-');
    // The binary names its sibling bundle, so moving the whole installation
    // keeps skills available and upgrades cannot mix code and guide versions.
    for (final name in skillDirectories) {
      await _copySkillDirectory(
        Directory(p.join(root, name)),
        Directory(p.join(staging.path, name)),
        deadline,
      );
    }
    final binary = p.join(staging.path, 'marionette-agent');
    final pending = Process.start('dart', [
      'compile',
      'exe',
      '-DMARIONETTE_AGENT_SKILL_BUNDLE=${p.basename(staging.path)}',
      entry,
      '-o',
      binary,
    ], workingDirectory: root);
    try {
      process = await pending.timeout(deadline.difference(DateTime.now()));
    } on TimeoutException {
      unawaited(
        pending.then((value) {
          value.kill(ProcessSignal.sigkill);
        }, onError: (Object _) {}),
      );
      rethrow;
    }
    final streams = Future.wait([
      process.stdout.drain<void>(),
      process.stderr.drain<void>(),
    ]);
    final code = await process.exitCode.timeout(
      deadline.difference(DateTime.now()),
    );
    await streams.timeout(deadline.difference(DateTime.now()));
    if (code != 0 || !File(binary).existsSync()) {
      throw const AgentError(
        'IO_ERROR',
        'CLI compilation failed; prepare the checkout dependencies and Dart SDK',
      );
    }
    if (!deadline.isAfter(DateTime.now())) {
      throw const AgentError('TIMEOUT', 'Installation deadline exceeded');
    }
    // Only a verified temporary binary replaces the explicitly selected target.
    await File(binary).rename(destination);
    reserved = false;
    installed = true;
    return {
      'installed': true,
      'action': action,
      'path': destination,
      'source': 'local_checkout',
    };
  } on AgentError {
    rethrow;
  } on TimeoutException {
    throw const AgentError('TIMEOUT', 'Installation deadline exceeded');
  } catch (_) {
    throw const AgentError(
      'IO_ERROR',
      'Cannot install CLI; check source, permissions and existing files',
    );
  } finally {
    process?.kill(ProcessSignal.sigkill);
    if (reserved && destination != null) {
      try {
        await File(destination).delete();
      } catch (_) {
        /* Preserve failure. */
      }
    }
    if (staging != null && !installed) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        /* Preserve failure. */
      }
    }
  }
}

Future<void> _copySkillDirectory(
  Directory source,
  Directory destination,
  DateTime deadline,
) async {
  if (!deadline.isAfter(DateTime.now())) {
    throw const AgentError('TIMEOUT', 'Installation deadline exceeded');
  }
  // Distribution sources must be self-contained, including their resources.
  if (await FileSystemEntity.type(source.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    invalid('Source must include regular skills and skill-data directories');
  }
  await destination.create();
  await for (final entry in source.list(followLinks: false)) {
    final target = p.join(destination.path, p.basename(entry.path));
    if (entry is Directory) {
      await _copySkillDirectory(entry, Directory(target), deadline);
    } else if (entry is File) {
      if (!deadline.isAfter(DateTime.now())) {
        throw const AgentError('TIMEOUT', 'Installation deadline exceeded');
      }
      await entry.copy(target);
    } else {
      invalid('Bundled skill resources must be regular files or directories');
    }
  }
}
