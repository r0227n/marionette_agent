import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../platform/screenshot_service.dart';
import 'screenshot_request.dart';

export 'screenshot_request.dart';
import 'command_context.dart';

Selector? snapshotFilter(Json params) {
  final options = {'interactive', 'compact', 'depth', 'source'};
  if (params.containsKey('source') &&
      !['flutter', 'native', 'all'].contains(params['source'])) {
    invalid('Invalid snapshot source');
  }
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

/// Images cross IPC; the CLI owns local path resolution and writing.
Future<Json> handleScreenshot(
  CommandContext context,
  Json params, {
  NativeScreenshotCapture captureNative = captureMacosScreenshot,
}) async {
  validateScreenshotRequest(params);
  if (params['source'] == 'macos') {
    context.check();
    final result = await captureNative(
      params['display'] as int,
      context.deadline,
    );
    context.check();
    return result;
  }
  return context.captureDeviceScreen(
    params['source'] as String? ?? 'ios-simulator',
    params['device'] as String,
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
