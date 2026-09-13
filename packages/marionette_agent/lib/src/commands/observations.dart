import 'package:args/args.dart';
import 'package:marionette_agent/marionette_agent.dart';

import 'arguments.dart';

CliCommand snapshotCommand() {
  final parser = ArgParser()
    ..addFlag('interactive', negatable: false)
    ..addFlag('compact', negatable: false)
    ..addOption('depth');
  addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    if (args.rest.isNotEmpty) invalid('Snapshot accepts only selector options');
    final params = <String, dynamic>{
      for (final kind in SelectorKind.values)
        if (args.wasParsed(kind.name)) kind.name: args.option(kind.name),
    };
    if (args.flag('interactive')) params['interactive'] = true;
    if (args.flag('compact')) params['compact'] = true;
    if (args.option('depth') != null) {
      final depth = int.tryParse(args.option('depth')!);
      if (depth == null || depth < 0) {
        invalid('Depth must be a non-negative integer');
      }
      params['depth'] = depth;
    }
    snapshotFilter(params);
    return params;
  });
}

Selector? snapshotFilter(Json params) {
  final options = {'interactive', 'compact', 'depth'};
  for (final flag in ['interactive', 'compact']) {
    if (params.containsKey(flag) && params[flag] is! bool) {
      invalid('Invalid snapshot flag');
    }
  }
  if (params.containsKey('depth') &&
      (params['depth'] is! int || (params['depth'] as int) < 0)) {
    invalid('Invalid snapshot depth');
  }
  params = {...params}..removeWhere((key, _) => options.contains(key));
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
    context.snapshot(
      filter: snapshotFilter(params),
      interactive: params['interactive'] == true,
      compact: params['compact'] == true,
      depth: params['depth'] as int?,
    );

CliCommand screenshotCommand() {
  final parser = ArgParser()..addFlag('annotate', negatable: false);
  addSelectorOptions(parser);
  return CliCommand(parser, (args) {
    final rest = args.rest.toList();
    final params = <String, Object?>{};
    for (final kind in SelectorKind.values) {
      if (args.wasParsed(kind.name)) params[kind.name] = args.option(kind.name);
    }
    if (rest.isNotEmpty && rest.first.startsWith('@')) {
      params['ref'] = rest.removeAt(0);
    }
    if (rest.length > 1 || (rest.isNotEmpty && rest.single.isEmpty)) {
      invalid('Usage: screenshot [ref|selector] [--annotate] [path]');
    }
    if (rest.isNotEmpty) params['path'] = rest.single;
    if (args.flag('annotate')) params['annotate'] = true;
    _screenshotTarget(params);
    return params;
  });
}

TargetQuery? _screenshotTarget(Json params) {
  final target = {...params}
    ..remove('path')
    ..remove('annotate');
  if (target.isEmpty) return null;
  if (params['annotate'] == true) {
    invalid('Crop and annotation cannot be combined');
  }
  if (target.keys.any(
    (key) =>
        key != 'ref' && !SelectorKind.values.any((kind) => kind.name == key),
  )) {
    invalid('Invalid screenshot target');
  }
  return decodeTarget(target);
}

/// Images cross IPC; the CLI owns local path resolution and writing.
Future<Json> handleScreenshot(CommandContext context, Json params) async {
  final target = _screenshotTarget(params);
  if ((params.containsKey('annotate') && params['annotate'] is! bool) ||
      (params.containsKey('path') &&
          (params['path'] is! String || (params['path'] as String).isEmpty))) {
    invalid('Usage: screenshot [--annotate] [path]');
  }
  if (target != null) {
    final before = await context.observeTarget(target);
    final capture = await context.read((backend) {
      if (backend is! MappedScreenshotBackend) {
        throw const AgentError(
          'UNSUPPORTED_CAPABILITY',
          'Crop requires screenshot geometry',
        );
      }
      return (backend as MappedScreenshotBackend).captureMappedScreenshot();
    });
    final after = await context.observeTarget(target);
    if (!before.sameAs(after)) {
      throw const AgentError(
        'STALE_REF',
        'Target changed during screenshot capture',
      );
    }
    return {
      'images': [capture.image],
      'geometry': capture.geometry.toJson(),
      'crop': before.bounds,
    };
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
