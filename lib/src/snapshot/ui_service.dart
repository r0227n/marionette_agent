import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

import '../commands/actions.dart';
import '../commands/native_request.dart';
import '../commands/observations.dart';
import '../commands/swipe.dart';
import '../platform/native/native_service.dart';
import '../protocol/protocol.dart';
import '../session/session.dart';
import 'snapshot_service.dart';

/// Publishes both observations and routes refs without retry or source fallback.
/// SessionManager holds session/device queues; adapters own source-specific matching.
class UiService {
  UiService(this.snapshots, this.native, this.sessions);
  final SnapshotService snapshots;
  final NativeService native;
  final Iterable<Session> Function() sessions;

  Json nativeParams(Execution execution, String action, Json params) {
    final target = execution.session.nativeTarget;
    if (target == null) {
      throw const AgentError(
        'NOT_CONNECTED',
        'Bind a device with session bind first',
      );
    }
    final split = target.indexOf(':');
    return {
      'action': action,
      'platform': target.substring(0, split),
      'device': target.substring(split + 1),
      ...params,
    };
  }

  bool blocked(List<dynamic> elements) => elements.any(
    (row) =>
        row['type'] == 'Alert' ||
        (row['package'] as String? ?? '').contains('permissioncontroller'),
  );

  Future<void> beforeFlutter(Execution execution) async {
    if (execution.session.nativeTarget == null) return;
    final params = nativeParams(execution, 'snapshot', {});
    try {
      final backend = native.backends[params['platform']];
      if (backend == null) {
        throw const AgentError(
          'UNSUPPORTED_CAPABILITY',
          'Native platform unavailable',
        );
      }
      final rows = await backend.inspect(
        params['device'] as String,
        execution.request.deadline,
      );
      execution.check();
      if (blocked(rows.map((row) => row.toJson()).toList())) {
        throw const AgentError(
          'UNRESOLVABLE_TARGET',
          'A native modal blocks Flutter input',
          hint: 'Run snapshot and operate the native modal first',
        );
      }
    } on PlatformException catch (error) {
      throw AgentError(error.code, error.message, hint: error.hint);
    }
    for (final other in sessions()) {
      if (other != execution.session &&
          other.nativeTarget == execution.session.nativeTarget) {
        other.invalidate();
      }
    }
  }

  Future<Json?> route(Execution execution, String command, Json params) async {
    if (command == 'snapshot') return observe(execution, params);
    final ref = params['ref'];
    if (!['tap', 'click', 'swipe'].contains(command)) {
      if (params['source'] == 'native' ||
          (ref is String && ref.startsWith('@n'))) {
        throw const AgentError(
          'UNSUPPORTED_CAPABILITY',
          'This operation does not support native targets',
        );
      }
      return null;
    }
    final clean = validateUiSource(params);
    if (command == 'swipe') {
      SwipeRequest.parse(clean, coordinates: true);
    } else {
      ActionRequest.parse(clean, fill: false);
    }
    if (params['source'] != 'native' &&
        !(ref is String && ref.startsWith('@n'))) {
      return null;
    }
    final mapped = <String, dynamic>{};
    for (final entry in clean.entries) {
      final key =
          const {
            'start-x': 'startX',
            'start-y': 'startY',
            'end-x': 'endX',
            'end-y': 'endY',
          }[entry.key] ??
          entry.key;
      mapped[key] =
          [
            'x',
            'y',
            'startX',
            'startY',
            'endX',
            'endY',
            'distance',
          ].contains(key)
          ? (entry.value is num
                ? entry.value
                : double.tryParse(entry.value.toString()))
          : entry.value;
    }
    return native.handle(
      execution,
      sessions(),
      nativeParams(execution, command == 'click' ? 'tap' : command, mapped),
    );
  }

  Future<Json> observe(Execution execution, Json params) async {
    execution.check();
    final filter = snapshotFilter(params);
    final source =
        params['source'] ??
        (execution.session.nativeTarget == null
            ? 'flutter'
            : execution.session.backend == null
            ? 'native'
            : 'all');
    final includeFlutter = source != 'native';
    final includeNative = source != 'flutter';
    if (includeNative &&
        (params['interactive'] == true ||
            params.containsKey('depth') ||
            filter?.kind.name == 'key')) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Native observations do not support interactive, depth or key filters',
      );
    }
    execution.session.invalidate();
    try {
      Json? flutter, os;
      if (includeFlutter) {
        flutter = await snapshots.publish(
          execution,
          filter: filter,
          interactive: params['interactive'] == true,
          compact: params['compact'] == true,
          depth: params['depth'] as int?,
        );
      }
      if (includeNative) {
        os = await native.handle(
          execution,
          sessions(),
          nativeParams(execution, 'snapshot', {}),
        );
      }
      execution.check();
      if (!includeNative) return flutter!;
      final nativeRows = (os!['elements'] as List)
          .where(
            (row) =>
                (filter == null || row[filter.kind.name] == filter.value) &&
                (params['compact'] != true ||
                    row['ref'] != null ||
                    (row['text'] as String? ?? '').isNotEmpty ||
                    row['value'] != null),
          )
          .toList();
      final modal = blocked(os['elements'] as List);
      final data = <String, dynamic>{
        'source': includeFlutter ? 'all' : 'native',
        'generation': flutter?['generation'] ?? snapshots.nextGeneration(),
        'platform': os['platform'],
        'device': os['device'],
        if (!includeFlutter) 'coordinateSpace': os['coordinateSpace'],
        'sources': {
          if (flutter != null)
            'flutter': {
              'status': 'ok',
              'coordinateSpace': 'flutter_logical_pixels',
            },
          'native': {
            'status': os.containsKey('limitation') ? 'limited' : 'ok',
            'coordinateSpace': os['coordinateSpace'],
            'limitation': os['limitation'],
          },
        },
        'occlusion': modal ? 'native_modal' : 'unknown',
        'elements': [
          for (final row in nativeRows)
            {
              ...asJson(row),
              'source': 'native',
              'coordinateSpace': os['coordinateSpace'],
              'actions': row['ref'] == null ? [] : ['tap', 'swipe'],
            },
          if (flutter != null)
            for (final raw in flutter['elements'] as List)
              {
                ...asJson(raw)
                  ..removeWhere((key, value) => modal && key == 'ref'),
                'source': 'flutter',
                'coordinateSpace': 'flutter_logical_pixels',
                if (modal) 'reason': 'blocked_by_native_modal',
              },
        ],
        if (os['limitation'] != null) 'limitation': os['limitation'],
      };
      snapshots.retainPublished(execution.session, data);
      native.retainPublished(execution.session, data);
      return data;
    } catch (_) {
      // A late read from a retired request must not erase a newer observation.
      execution.check();
      execution.session.invalidate();
      rethrow;
    }
  }
}
