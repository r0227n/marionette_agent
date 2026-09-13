import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';

// Internal API boundary for fixed dependencies approved in ARCHITECTURE.
// ignore: implementation_imports
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

import '../protocol/protocol.dart';
import 'backend.dart';

/// The only production module allowed to import upstream internal APIs.
class MarionetteBackend
    implements
        Backend,
        MappedScreenshotBackend,
        InteractionBackend,
        ClipboardBackend {
  MarionetteBackend({VmServiceConnector? connector})
    : _connector = connector ?? VmServiceConnector();
  final VmServiceConnector _connector;
  bool _extended = false;
  Set<String> _extraInteractions = const {};
  @override
  Set<SelectorKind> get selectors => const {
    SelectorKind.key,
    SelectorKind.text,
    SelectorKind.type,
  };

  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AgentError {
      rethrow;
    } on NotConnectedException {
      throw const AgentError('CONNECTION_LOST', 'Backend is disconnected');
    } on RPCError catch (e) {
      throw _rpcError(e.code, e.message);
    } on VmServiceExtensionException catch (e) {
      throw _rpcError(e.errorCode, e.error);
    } on SocketException {
      throw const AgentError('CONNECTION_LOST', 'VM Service connection lost');
    } on WebSocketException {
      throw const AgentError('CONNECTION_LOST', 'VM Service connection lost');
    } on StateError {
      throw const AgentError('CONNECTION_LOST', 'VM Service connection closed');
    } on TimeoutException {
      throw const AgentError('TIMEOUT', 'Backend deadline exceeded');
    } catch (_) {
      throw const AgentError(
        'BACKEND_ERROR',
        'Backend request failed',
        outcome: Outcome.unknown,
      );
    }
  }

  // vm_service 15.3 reports disposal both as kServerError with this exact
  // message and as kConnectionDisposed. Neither proves an operation failed.
  AgentError _rpcError(int? code, String? message) {
    if (code == RPCErrorKind.kConnectionDisposed.code ||
        code == RPCErrorKind.kServiceDisappeared.code ||
        (code == RPCErrorKind.kServerError.code &&
            message == 'Service connection disposed')) {
      return const AgentError(
        'CONNECTION_LOST',
        'VM Service connection closed',
      );
    }
    if (code == RPCErrorKind.kMethodNotFound.code) {
      return const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not support this operation',
      );
    }
    return const AgentError(
      'BACKEND_ERROR',
      'Binding rejected the operation',
      outcome: Outcome.failed,
    );
  }

  @override
  Future<void> connect(Uri uri) => _call(() async {
    await _connector.connect(uri.toString());
    final extensions = await _connector.listExtensions();
    final list = extensions['extensions'];
    _extended =
        list is List &&
        list.any(
          (entry) =>
              entry is Map && entry['name'] == 'marionette_agent.inspect',
        );
    if (_extended) {
      final response = validateResponse(
        await _connector.callCustomExtension('marionette_agent.inspect'),
      );
      if (response['version'] != 1 ||
          response['interactions'] is! List ||
          (response['interactions'] as List).any((entry) => entry is! String)) {
        throw const AgentError(
          'UNSUPPORTED_CAPABILITY',
          'Unsupported typed observation provider',
        );
      }
      _extraInteractions = (response['interactions'] as List)
          .cast<String>()
          .toSet();
    }
  });
  @override
  Set<String> get interactions => {'dblclick', 'press', ..._extraInteractions};

  @override
  Future<void> interact(
    String action, {
    Selector? target,
    Json arguments = const {},
  }) {
    if (_extraInteractions.contains(action)) {
      return _call(() async {
        await extensionInteraction(
          action,
          target: target,
          arguments: arguments,
        );
      });
    }
    switch (action) {
      case 'dblclick':
        return _action(() => _connector.doubleTap(_selector(target!)));
      case 'press':
        return _action(
          () => _connector.pressKey(
            arguments['key'] as String,
            modifiers: (arguments['modifiers'] as List).cast<String>().join(
              ',',
            ),
          ),
        );
      default:
        throw const AgentError(
          'UNSUPPORTED_CAPABILITY',
          'Binding does not support this interaction',
        );
    }
  }

  @override
  Future<void> disconnect() => _call(() async {
    try {
      if (_extraInteractions.contains('keyboard.release')) {
        await extensionInteraction('keyboard.release')
            .timeout(const Duration(seconds: 1));
      }
    } catch (_) {
      /* Always disconnect even if the app cannot release input. */
    } finally {
      await _connector.disconnect();
    }
  });

  @override
  Future<String?> readClipboard() => _call(() async {
    if (!_extraInteractions.contains('clipboard.read')) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not provide target clipboard access',
      );
    }
    final result = await extensionInteraction('clipboard.read');
    if (result['text'] != null && result['text'] is! String) {
      throw const AgentError('BACKEND_ERROR', 'Invalid clipboard response');
    }
    return result['text'] as String?;
  });
  @override
  Future<void> checkConnection() => _call(() async {
    await _connector.getVersion();
  });

  /// Validate structured status from fixed binding instead of message text.
  static Json validateResponse(Map<String, dynamic> response) {
    if (response['status'] != 'Success') {
      throw const AgentError(
        'BACKEND_ERROR',
        'Invalid binding response',
        outcome: Outcome.unknown,
      );
    }
    return Map<String, Object?>.from(response);
  }

  /// Drop diagnostic properties and separate semantics where observation and matcher semantics differ.
  static List<ElementInfo> decodeElements(Map<String, dynamic> response) {
    final value = validateResponse(response)['elements'];
    if (value is! List) {
      throw const AgentError('BACKEND_ERROR', 'Invalid element list');
    }
    return value.map((raw) {
      final e = _elementObject(raw);
      for (final key in [
        'type',
        'text',
        'key',
        'identifier',
        'inputValue',
        'role',
        'label',
        'placeholder',
      ]) {
        if (e[key] != null && e[key] is! String) {
          throw const AgentError('BACKEND_ERROR', 'Invalid element attribute');
        }
      }
      if ([
        'visible',
        'enabled',
        'checked',
        'interactive',
      ].any((key) => e[key] != null && e[key] is! bool)) {
        throw const AgentError('BACKEND_ERROR', 'Invalid visibility');
      }
      if (e['depth'] != null &&
          (e['depth'] is! int || (e['depth'] as int) < 0)) {
        throw const AgentError('BACKEND_ERROR', 'Invalid element depth');
      }
      Json? bounds;
      if (e['bounds'] != null) {
        final b = _elementObject(e['bounds']);
        bounds = {};
        for (final key in ['x', 'y', 'width', 'height']) {
          final n = b[key];
          if (n is! num ||
              !n.isFinite ||
              (['width', 'height'].contains(key) && n < 0)) {
            throw const AgentError('BACKEND_ERROR', 'Invalid bounds');
          }
          bounds[key] = n.toDouble();
        }
      }
      return ElementInfo(
        type: e['type'] as String?,
        text: e['text'] as String?,
        key: e['key'] as String?,
        identifier: e['identifier'] as String?,
        bounds: bounds,
        visible: e['visible'] as bool?,
        inputValue: e['inputValue'] as String?,
        enabled: e['enabled'] as bool?,
        checked: e['checked'] as bool?,
        role: e['role'] as String?,
        label: e['label'] as String?,
        placeholder: e['placeholder'] as String?,
        depth: e['depth'] as int?,
        interactive: e['interactive'] as bool?,
        // The wire format does not identify Semantics subclasses or custom
        // extractors. Only these exact types have a verified matcher source
        // in binding 0.6.0. Other types can still use keys or unique types.
        textMatchable: const {
          'Text',
          'RichText',
          'EditableText',
          'TextField',
          'TextFormField',
        }.contains(e['type']),
      );
    }).toList();
  }

  static Json _elementObject(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const AgentError('BACKEND_ERROR', 'Invalid element object');
    }
    return Map<String, Object?>.from(value);
  }

  Json _selector(Selector selector) {
    if (!selectors.contains(selector.kind)) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not support this selector',
      );
    }
    return selector.toJson();
  }

  Future<void> _action(Future<Map<String, dynamic>> Function() call) =>
      _call(() async {
        validateResponse(await call());
      });
  @override
  Future<List<ElementInfo>> inspect() => _call(
    () async => decodeElements(
      _extended
          ? await _connector.callCustomExtension('marionette_agent.inspect')
          : await _connector.getInteractiveElements(),
    ),
  );
  @override
  Future<void> tap(TapTarget target) {
    final args = switch (target) {
      ElementTarget(:final selector) => _selector(selector),
      CoordinateTarget(:final point) => <String, Object?>{
        'x': point.x.toString(),
        'y': point.y.toString(),
      },
    };
    return _action(() => _connector.tap(args));
  }

  @override
  Future<void> fill(Selector selector, String text) {
    final args = _selector(selector);
    return _action(() => _connector.enterText(args, text));
  }

  @override
  Future<void> swipe(SwipeGesture gesture) {
    final args = switch (gesture) {
      ElementSwipe(:final selector, :final direction, :final distance) => {
        ..._selector(selector),
        'direction': direction.name,
        'distance': distance.toString(),
      },
      CoordinateSwipe(:final start, :final end) => <String, Object?>{
        'startX': start.x.toString(),
        'startY': start.y.toString(),
        'endX': end.x.toString(),
        'endY': end.y.toString(),
      },
    };
    return _action(() => _connector.swipe(args));
  }

  @override
  Future<List<String>> captureScreenshots() => _call(() async {
    final images = validateResponse(
      await _connector.takeScreenshots(),
    )['screenshots'];
    if (images is! List ||
        images.isEmpty ||
        images.any((e) => e is! String || e.isEmpty)) {
      throw const AgentError('BACKEND_ERROR', 'No valid screenshots returned');
    }
    return images.cast<String>();
  });
  @override
  Future<LogBatch> readLogs() => _call(() async {
    Map<String, dynamic> response;
    try {
      response = await _connector.getLogs();
    } on VmServiceExtensionException catch (e) {
      if (e.errorCode == -32000 &&
          (e.error?.contains('Log collection is not configured') ?? false)) {
        return const LogBatch([], configured: false);
      }
      rethrow;
    }
    final logs = validateResponse(response)['logs'];
    if (logs is! List || logs.any((e) => e is! String)) {
      throw const AgentError('BACKEND_ERROR', 'Invalid logs response');
    }
    return LogBatch(logs.cast<String>(), configured: true);
  });

  Future<Json> extensionInteraction(
    String action, {
    Selector? target,
    Json arguments = const {},
  }) => _call(() async {
    final response = validateResponse(
      await _connector.callCustomExtension('marionette_agent.interact', {
        'request': jsonEncode({
          'action': action,
          if (target != null) 'target': target.toJson(),
          'arguments': arguments,
        }),
      }),
    );
    final code = response['errorCode'];
    if (code != null) {
      const allowed = {
        'INVALID_ARGUMENT',
        'UNSUPPORTED_CAPABILITY',
        'TARGET_NOT_FOUND',
        'AMBIGUOUS_TARGET',
        'UNRESOLVABLE_TARGET',
        'BACKEND_ERROR',
      };
      throw AgentError(
        allowed.contains(code) ? code as String : 'BACKEND_ERROR',
        'Typed provider rejected the interaction',
        outcome: Outcome.failed,
      );
    }
    return {...response}..remove('status');
  });

  @override
  Future<MappedScreenshot> captureMappedScreenshot() => _call(() async {
    final response = await _connector.callCustomExtension(
      'marionette_agent.captureMappedScreenshot',
    );
    if (response['status'] != 'Success' || response['supported'] != true) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding cannot verify screenshot view geometry',
      );
    }
    final images = response['screenshots'];
    if (images is! List ||
        images.length != 1 ||
        images.single is! String ||
        response['geometry'] is! Map) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'A single mapped screenshot is required',
      );
    }
    return MappedScreenshot(
      images.single as String,
      ScreenshotGeometry.decode(response['geometry']),
    );
  });
}
