import 'dart:convert';

import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

import '../../commands/native_request.dart';
import '../../protocol/protocol.dart';
import '../../session/session.dart';

class _Observation {
  _Observation(this.target, this.refs);
  final String target;
  final Map<String, NativeElement> refs;
}

/// Composes platform adapters and native ref validation. SessionManager owns
/// lifetime/policy; Execution owns deadlines and the single-send guard.
class NativeService {
  NativeService({Map<String, NativeUiBackend>? backends})
    : backends =
          backends ??
          {'ios': const IosNativeUi(), 'android': const AndroidNativeUi()};
  final Map<String, NativeUiBackend> backends;
  int _nextRef = 0;

  Future<Json> handle(
    Execution execution,
    Iterable<Session> sessions,
    Json params,
  ) async {
    validateNative(params);
    final platform = params['platform'] as String,
        device = params['device'] as String;
    final target = '$platform:$device';
    // Caller holds the device queue across observation and dispatch.
    return await (() async {
      execution.check();
      try {
        final backend = backends[platform];
        if (backend == null) {
          throw const AgentError(
            'UNSUPPORTED_CAPABILITY',
            'Native platform is unavailable',
          );
        }
        final session = execution.session;
        final deadline = execution.request.deadline;
        final metadata = <String, Object?>{
          'source': 'native',
          'platform': platform,
          'device': device,
          'coordinateSpace': platform == 'ios'
              ? 'screen_points'
              : 'screen_pixels',
        };
        // Explicit coordinates are also usable when accessibility cannot dump
        // a system-hosted surface or the app never becomes idle.
        final elements =
            params['action'] == 'snapshot' ||
                (params['action'] == 'tap' && !params.containsKey('x')) ||
                (params['action'] == 'swipe' && params.containsKey('direction'))
            ? await backend.inspect(device, deadline)
            : <NativeElement>[];
        execution.check();
        if (params['action'] == 'snapshot') {
          final fingerprints = <String, int>{};
          for (final element in elements) {
            final key = jsonEncode(element.toJson());
            fingerprints[key] = (fingerprints[key] ?? 0) + 1;
          }
          final refs = <String, NativeElement>{};
          final rows = <Json>[];
          for (final element in elements) {
            final reason = !element.tappable || element.type == 'Application'
                ? 'not_tappable'
                : fingerprints[jsonEncode(element.toJson())] != 1
                ? 'ambiguous_native_element'
                : null;
            final ref = reason == null ? '@n${++_nextRef}' : null;
            if (ref != null) refs[ref] = element;
            rows.add({...element.toJson(), 'ref': ref, 'reason': ?reason});
          }
          session.nativeTarget = target;
          session.nativeObservation = _Observation(target, refs);
          return {
            ...metadata,
            'elements': rows,
            if (elements.isEmpty ||
                elements.every((e) => e.type == 'Application'))
              'limitation': 'Native accessibility exposed no child elements. Inspect the device screen before using explicit coordinates. No automatic coordinate fallback is performed.',
          };
        }
        double? x, y;
        if (params['action'] == 'tap' || params.containsKey('direction')) {
          if (params.containsKey('x')) {
            x = nativeCoordinate(params['x']);
            y = nativeCoordinate(params['y']);
          } else {
            final ref = params['ref'];
            late List<NativeElement> matches;
            if (ref != null) {
              final observed = session.nativeObservation;
              if (observed is! _Observation ||
                  observed.target != target ||
                  !observed.refs.containsKey(ref)) {
                throw const AgentError(
                  'STALE_REF',
                  'Native ref is stale',
                  hint: 'Run snapshot again',
                );
              }
              final fingerprint = jsonEncode(observed.refs[ref]!.toJson());
              matches = elements
                  .where((e) => jsonEncode(e.toJson()) == fingerprint)
                  .toList();
            } else {
              final key = [
                'text',
                'identifier',
                'type',
              ].singleWhere(params.containsKey);
              matches = elements
                  .where((e) => e.toJson()[key] == params[key])
                  .toList();
            }
            if (matches.isEmpty) {
              throw AgentError(
                ref == null ? 'TARGET_NOT_FOUND' : 'STALE_REF',
                'Native target is absent or changed',
              );
            }
            if (matches.length != 1) {
              throw const AgentError(
                'AMBIGUOUS_TARGET',
                'Native target matches multiple elements',
              );
            }
            final element = matches.single;
            if (!element.tappable) {
              throw const AgentError(
                'UNRESOLVABLE_TARGET',
                'Native element is disabled or has no usable bounds',
              );
            }
            x = element.bounds.x + element.bounds.width / 2;
            y = element.bounds.y + element.bounds.height / 2;
          }
        }
        if (params['action'] == 'swipe' && params.containsKey('direction')) {
          final distance = nativeCoordinate(params['distance'] ?? 200);
          final direction = params['direction'];
          params = {
            ...params,
            'startX': x,
            'startY': y,
            'endX':
                x! +
                (direction == 'left'
                    ? -distance
                    : direction == 'right'
                    ? distance
                    : 0),
            'endY':
                y! +
                (direction == 'up'
                    ? -distance
                    : direction == 'down'
                    ? distance
                    : 0),
          };
          for (final key in ['startX', 'startY', 'endX', 'endY']) {
            nativeCoordinate(params[key]);
          }
        }
        execution.check();
        session.nativeTarget = target;
        // VM connections do not prove which native device they belong to.
        // Conservatively expire Flutter refs in every session of this daemon.
        for (final other in sessions) {
          other.observation = null;
          if (other.nativeTarget == target) other.nativeObservation = null;
        }
        await execution.mutateExternal(
          () => params['action'] == 'tap'
              ? backend.tap(device, x!, y!, deadline)
              : backend.swipe(
                  device,
                  nativeCoordinate(params['startX']),
                  nativeCoordinate(params['startY']),
                  nativeCoordinate(params['endX']),
                  nativeCoordinate(params['endY']),
                  deadline,
                ),
        );
        return {
          ...metadata,
          'action': params['action'],
          'requiresSnapshot': true,
        };
      } on PlatformException catch (e) {
        throw AgentError(
          e.code,
          e.message,
          hint: e.hint,
          outcome: execution.sent ? Outcome.unknown : Outcome.notSent,
        );
      }
    })();
  }

  void retainPublished(Session session, Json data) {
    if (data['finalSnapshot'] is Map) data = asJson(data['finalSnapshot']);
    final observed = session.nativeObservation;
    if (observed is! _Observation || data['elements'] is! List) return;
    final refs = (data['elements'] as List)
        .map((e) => (e as Map)['ref'])
        .toSet();
    observed.refs.removeWhere((key, _) => !refs.contains(key));
  }
}
