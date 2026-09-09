import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

CliCommand screenshotCommand() => CliCommand(ArgParser(), (args) {
  if (args.rest.length > 1 ||
      (args.rest.isNotEmpty && args.rest.single.isEmpty)) {
    invalid('Usage: screenshot [path]');
  }
  return {if (args.rest.isNotEmpty) 'path': args.rest.single};
});

/// Images cross IPC; the CLI owns local path resolution and writing.
Future<Json> handleScreenshot(CommandContext context, Json params) {
  if (params.keys.any((k) => k != 'path') ||
      (params.containsKey('path') &&
          (params['path'] is! String || (params['path'] as String).isEmpty))) {
    invalid('Usage: screenshot [path]');
  }
  return context.read(
    (backend) async => {'images': await backend.captureScreenshots()},
  );
}

Future<Json> handleLogs(CommandContext context, Json params) {
  if (params.isNotEmpty) invalid('Usage: logs');
  return context.read((backend) async {
    final batch = await backend.readLogs();
    return {
      'entries': batch.entries,
      'configured': batch.configured,
      if (batch.limitation != null) 'limitation': batch.limitation,
      if (batch.configured == null && batch.limitation == null) 'limitation': 'The backend cannot distinguish unconfigured collection from an empty log range.',
    };
  });
}
