import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart' hide Version;
import 'package:pub_semver/pub_semver.dart';

// Internal API boundary for dependencies approved in ARCHITECTURE.
// ignore: implementation_imports
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

import '../protocol/protocol.dart';
import 'backend.dart';

/// The only production module allowed to import upstream internal APIs.
class MarionetteBackend
    implements Backend, InteractionBackend, ClipboardBackend {
  MarionetteBackend({VmServiceConnector? connector})
    : _connector = connector ?? VmServiceConnector();
  final VmServiceConnector _connector;
  bool _extended = false;
  bool _hasVersion = false;
  bool _legacyEnvelope = false;
  Version? _bindingVersion;
  Set<String> _extraInteractions = const {};
  @override
  Set<SelectorKind> get selectors => {
    SelectorKind.key,
    SelectorKind.text,
    if (!_legacyEnvelope) SelectorKind.type,
    if (_bindingVersion != null && _bindingVersion! >= Version(0, 7, 0))
      SelectorKind.identifier,
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
    _extended = false;
    _extraInteractions = const {};
    _hasVersion = false;
    _legacyEnvelope = false;
    _bindingVersion = null;
    await _connector.connect(uri.toString());
    final version = await _optionalRead(_connector.getVersion);
    _hasVersion = version != null;
    if (version != null) {
      _bindingVersion = Version.parse(version);
    } else {
      // Before 0.4 there is no version endpoint. Flutter overwrites 0.1
      // type with _extensionType; only 0.2+ preserve a status discriminator.
      final response = await _connector.getInteractiveElements(
        compaction: 'none',
      );
      _legacyEnvelope =
          !response.containsKey('status') &&
          response['type'] == '_extensionType' &&
          response['method'] == 'ext.flutter.marionette.interactiveElements';
      _bindingResponse(response, 'interactiveElements');
    }
    final extensions = await _optionalRead(_connector.listExtensions);
    final list = extensions?['extensions'];
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

  // Only missing read-only discovery endpoints are optional. Connection,
  // timeout and malformed-response failures must still fail the request.
  Future<T?> _optionalRead<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on VmServiceExtensionException catch (error) {
      if (error.errorCode != RPCErrorKind.kMethodNotFound.code) rethrow;
    } on RPCError catch (error) {
      if (error.code != RPCErrorKind.kMethodNotFound.code) rethrow;
    }
    return null;
  }

  Json _bindingResponse(Map<String, dynamic> response, String method) {
    if (_legacyEnvelope && !response.containsKey('status')) {
      // In 0.1 Flutter overwrites the binding's type:Success/Error. Its
      // failure payload always has error; success has the method's result.
      // Require the exact VM envelope and shape, never a success message.
      if (response['type'] != '_extensionType' ||
          response['method'] != 'ext.flutter.marionette.$method') {
        throw const AgentError(
          'BACKEND_ERROR',
          'Invalid legacy binding envelope',
        );
      }
      if (response.containsKey('error') || response.containsKey('stackTrace')) {
        throw const AgentError(
          'BACKEND_ERROR',
          'Binding rejected the operation',
          outcome: Outcome.failed,
        );
      }
      final valid = switch (method) {
        'interactiveElements' => response['elements'] is List,
        'getLogs' => response['logs'] is List,
        'tap' || 'enterText' => response['message'] is String,
        _ => false,
      };
      if (!valid) {
        throw const AgentError(
          'BACKEND_ERROR',
          'Invalid legacy binding response',
        );
      }
      return {...response, 'status': 'Success'};
    }
    return validateResponse(response);
  }

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
        return _action(
          'doubleTap',
          () => _connector.doubleTap(_selector(target!)),
        );
      case 'press':
        return _action(
          'pressKey',
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
    if (_hasVersion) {
      await _connector.getVersion();
    } else {
      _bindingResponse(
        await _connector.getInteractiveElements(compaction: 'none'),
        'interactiveElements',
      );
    }
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

  Future<void> _action(
    String method,
    Future<Map<String, dynamic>> Function() call,
  ) => _call(() async {
    _bindingResponse(await call(), method);
  });
  @override
  Future<List<ElementInfo>> inspect() => _call(() async {
    if (_extended) {
      return decodeElements(
        await _connector.callCustomExtension('marionette_agent.inspect'),
      );
    }
    final response = _bindingResponse(
      // 0.7 compaction omits visible:true. Ask for explicit observations;
      // older bindings ignore this read-only parameter.
      await _connector.getInteractiveElements(compaction: 'none'),
      'interactiveElements',
    );
    final elements = response['elements'];
    if (elements is! List) {
      throw const AgentError('BACKEND_ERROR', 'Invalid element list');
    }
    return decodeElements({
      ...response,
      'elements': elements.map((raw) {
        final element = _elementObject(raw);
        // Binding 0.6.0 flattens debugFillProperties into string diagnostics.
        // Only these explicit protocol fields are observations in legacy mode;
        // names such as enabled/checked must not acquire typed-provider meaning.
        return {
          for (final key in ['type', 'text', 'key', 'bounds', 'visible'])
            if (element.containsKey(key)) key: element[key],
          if (selectors.contains(SelectorKind.identifier) &&
              element.containsKey('identifier'))
            'identifier': element['identifier'],
          // 0.2/0.3 omit extracted text, but Text.data is the exact string
          // used by their Text matcher. Other diagnostics are not typed data.
          if (!_hasVersion &&
              !element.containsKey('text') &&
              element['type'] == 'Text' &&
              element['data'] is String)
            'text': element['data'],
        };
      }).toList(),
    });
  });
  @override
  Future<void> tap(TapTarget target) {
    if (_legacyEnvelope && target is CoordinateTarget) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Binding does not support coordinate taps',
      );
    }
    final args = switch (target) {
      ElementTarget(:final selector) => _selector(selector),
      CoordinateTarget(:final point) => <String, Object?>{
        'x': point.x.toString(),
        'y': point.y.toString(),
      },
    };
    return _action('tap', () => _connector.tap(args));
  }

  @override
  Future<void> fill(Selector selector, String text) {
    final args = _selector(selector);
    return _action('enterText', () => _connector.enterText(args, text));
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
    return _action('swipe', () => _connector.swipe(args));
  }

  @override
  Future<LogBatch> readLogs() => _call(() async {
    Map<String, dynamic> response;
    try {
      response = await _connector.getLogs();
    } on VmServiceExtensionException catch (e) {
      if ((e.errorCode == -32000 || e.errorCode == -32016) &&
          (e.error?.contains('Log collection is not configured') ?? false)) {
        return const LogBatch([], configured: false);
      }
      rethrow;
    }
    final logs = _bindingResponse(response, 'getLogs')['logs'];
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
}
