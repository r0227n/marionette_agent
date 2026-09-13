import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

CliCommand snapshotCommand() {
  final parser = ArgParser();
  addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    if (args.rest.isNotEmpty) invalid('Snapshot accepts only selector options');
    final params = <String, dynamic>{
      for (final kind in SelectorKind.values)
        if (args.wasParsed(kind.name)) kind.name: args.option(kind.name),
    };
    snapshotFilter(params);
    return params;
  });
}

Selector? snapshotFilter(Json params) {
  if (params.isEmpty) return null;
  final kinds = SelectorKind.values.where(
    (kind) => params.containsKey(kind.name),
  );
  if (params.length != 1 || kinds.length != 1) {
    invalid(
      'Snapshot accepts exactly one key, identifier, text, or type filter',
    );
  }
  final kind = kinds.single;
  final value = params[kind.name];
  if (value is! String || value.isEmpty) {
    invalid('Filter must be a nonempty string');
  }
  return Selector(kind, value);
}

Future<Json> handleSnapshot(CommandContext context, Json params) =>
    context.snapshot(filter: snapshotFilter(params));

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
