import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

CliCommand screenshotCommand() =>
    CliCommand(ArgParser()..addFlag('annotate', negatable: false), (args) {
      if (args.rest.length > 1 ||
          (args.rest.isNotEmpty && args.rest.single.isEmpty)) {
        invalid('Usage: screenshot [--annotate] [path]');
      }
      return {
        if (args.rest.isNotEmpty) 'path': args.rest.single,
        if (args.flag('annotate')) 'annotate': true,
      };
    });

/// Images cross IPC; the CLI owns local path resolution and writing.
Future<Json> handleScreenshot(CommandContext context, Json params) async {
  if (params.keys.any((k) => k != 'path' && k != 'annotate') ||
      (params.containsKey('annotate') && params['annotate'] is! bool) ||
      (params.containsKey('path') &&
          (params['path'] is! String || (params['path'] as String).isEmpty))) {
    invalid('Usage: screenshot [--annotate] [path]');
  }
  if (params['annotate'] == true) {
    final annotations = await context.annotationTargets();
    final capture = await context.read((backend) {
      if (backend is! MappedScreenshotBackend) {
        throw const AgentError(
          'UNSUPPORTED_CAPABILITY',
          'Binding does not provide screenshot geometry',
        );
      }
      return (backend as MappedScreenshotBackend).captureMappedScreenshot();
    });
    await context.annotationTargets();
    return {
      'images': [capture.image],
      'geometry': capture.geometry.toJson(),
      'annotations': annotations,
    };
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
