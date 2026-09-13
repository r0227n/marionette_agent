import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../platform_exception.dart';
import 'recorder.dart';

import 'web_target.dart';

const _lost = PlatformException(
  'CONNECTION_LOST',
  'Chrome recording target closed or disconnected',
  hint: 'Keep the selected tab open; no replacement tab or display is selected automatically.',
);

/// Records the explicitly selected whole display via the native backend, while
/// supervising the selected Chrome tab. It never renders/captures Flutter frames.
class WebScreenRecorder implements ScreenRecorder {
  const WebScreenRecorder(
    this.displayRecorder, {
    this.captureAllowed = _captureAllowed,
  });
  final bool Function() captureAllowed;
  final ScreenRecorder displayRecorder;

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) async {
    final selected = WebRecordingTarget.parse(target.device);
    if (selected == null) {
      throw const PlatformException(
        'INVALID_ARGUMENT',
        'Expected display:<index>@ws://127.0.0.1:<port>/devtools/page/<target-id>',
      );
    }
    if (!Platform.isMacOS) {
      throw const PlatformException(
        'UNSUPPORTED_CAPABILITY',
        'Web display recording currently supports macOS hosts only',
      );
    }
    if (!captureAllowed()) {
      throw const PlatformException(
        'IO_ERROR',
        'macOS screen recording permission is not granted',
        hint: 'Enable Screen Recording for the terminal/host app in macOS System Settings, then explicitly start a new recording.',
      );
    }
    _ChromeDisplayRecording? handle;
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final connecting = WebSocket.connect(
        selected.endpoint.toString(),
        customClient: client,
      );
      // Dispose a late upgrade too: timeout is not cancellation of connect.
      var expired = false;
      unawaited(
        connecting.then((socket) {
          if (expired) unawaited(socket.close());
        }, onError: (Object _) {}),
      );
      late WebSocket socket;
      try {
        socket = await connecting.timeout(_remaining(deadline));
      } finally {
        expired = true;
      }
      handle = _ChromeDisplayRecording(socket, client);
      final version = await handle.command('Browser.getVersion', deadline);
      if (version['product'] is! String ||
          !RegExp(r'^(Headless)?Chrome/')
              .hasMatch(version['product'] as String)) {
        throw const PlatformException(
          'UNSUPPORTED_CAPABILITY',
          'This Web backend requires Google Chrome',
        );
      }
      if ((version['product'] as String).startsWith('Headless')) {
        throw const PlatformException(
          'UNSUPPORTED_CAPABILITY',
          'Whole-display Web recording requires visible Chrome',
        );
      }
      final info = await handle.command('Target.getTargetInfo', deadline);
      final targetInfo = info['targetInfo'];
      if (targetInfo is! Map ||
          targetInfo['type'] != 'page' ||
          targetInfo['targetId'] != selected.endpoint.pathSegments.last) {
        throw const PlatformException(
          'INVALID_ARGUMENT',
          'The endpoint must identify the selected Chrome page tab',
        );
      }
      await handle.command('Inspector.enable', deadline);
      handle.check();
      // All OS permissions, tool startup and movie finalization stay in the
      // existing native backend; never fall back to a narrower tab screencast.
      final native = await displayRecorder.start(
        RecordingTarget(RecordingPlatform.macos, selected.display),
        stagingPath,
        deadline,
      );
      handle.native = native;
      if (handle.failed) {
        await native.stop().catchError((Object _) {});
        handle.check();
      }
      handle.watch();
      _remaining(deadline);
      return handle;
    } on TimeoutException {
      await handle?.abort();
      client.close(force: true);
      throw const PlatformException(
        'TIMEOUT',
        'Chrome recording did not become ready before the deadline',
      );
    } on PlatformException {
      await handle?.abort();
      client.close(force: true);
      rethrow;
    } catch (_) {
      await handle?.abort();
      client.close(force: true);
      throw const PlatformException(
        'CONNECTION_LOST',
        'Cannot attach to the selected Chrome page',
        hint: 'Start visible Chrome with a separate --user-data-dir and loopback --remote-debugging-port; use its exact page endpoint. Check debugging policy and access permissions.',
      );
    }
  }
}

bool _captureAllowed() {
  try {
    final library = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
    );
    return library.lookupFunction<Bool Function(), bool Function()>(
      'CGPreflightScreenCaptureAccess',
    )();
  } catch (_) {
    throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'macOS screen recording permission API is unavailable',
    );
  }
}

Duration _remaining(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) throw TimeoutException('deadline');
  return remaining;
}

class _ChromeDisplayRecording implements RecordingHandle {
  _ChromeDisplayRecording(this.socket, this.client) {
    socket.listen(
      _message,
      onError: (Object _) => _fail(_lost),
      onDone: () {
        if (!_closing) _fail(_lost);
      },
    );
  }
  final WebSocket socket;
  final HttpClient client;
  final _ended = Completer<void>();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 0;
  RecordingHandle? native;
  Future<void>? _stopping;
  PlatformException? _failure;
  bool _closing = false;
  bool get failed => _failure != null;

  @override
  Future<void> get ended => _ended.future;
  @override
  bool get isRunning => native?.isRunning ?? !_ended.isCompleted;
  void check() {
    if (_failure != null) throw _failure!;
  }

  Future<Map<String, dynamic>> command(String method, DateTime deadline) async {
    check();
    final id = ++_nextId;
    final done = Completer<Map<String, dynamic>>();
    _pending[id] = done;
    try {
      socket.add(
        jsonEncode({'id': id, 'method': method, 'params': <String, Object?>{}}),
      );
      return await done.future.timeout(_remaining(deadline));
    } finally {
      _pending.remove(id);
    }
  }

  void _message(dynamic raw) {
    try {
      if (raw is! String || raw.length > 1024 * 1024) throw _lost;
      final message = jsonDecode(raw) as Map<String, dynamic>;
      final pending = _pending[message['id']];
      if (pending != null && !pending.isCompleted) {
        if (message.containsKey('error')) {
          // Server text can include page content or URLs: expose only a safe hint.
          final error = message['error'];
          pending.completeError(
            PlatformException(
              error is Map && error['code'] == -32601
                  ? 'UNSUPPORTED_CAPABILITY'
                  : 'IO_ERROR',
              'Chrome rejected the recording protocol command',
              hint: 'Check Chrome version, debugging policy and permission to attach to this target.',
            ),
          );
        } else {
          pending.complete(Map<String, dynamic>.from(message['result'] as Map));
        }
      } else if (message['method'] == 'Inspector.detached' ||
          message['method'] == 'Inspector.targetCrashed') {
        _fail(_lost);
      }
    } catch (_) {
      _fail(_lost);
    }
  }

  void watch() {
    unawaited(
      native!.ended.then(
        (_) {
          if (!_closing) unawaited(stop().catchError((Object _) {}));
        },
        onError: (Object _) {
          _fail(
            const PlatformException(
              'IO_ERROR',
              'Native display recording failed',
            ),
          );
        },
      ),
    );
  }

  void _fail(PlatformException error) {
    _failure ??= error;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(_failure!);
    }
    // Startup owns cleanup until the native handle has been attached.
    if (native != null && !_closing) {
      unawaited(stop().catchError((Object _) {}));
    }
  }

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    _closing = true;
    try {
      await native?.stop();
    } on PlatformException catch (error) {
      _failure ??= error;
    } catch (_) {
      _failure ??= const PlatformException(
        'IO_ERROR',
        'Cannot finalize Chrome display recording',
      );
    } finally {
      unawaited(socket.close().catchError((Object _) {}));
      client.close(force: true);
      final capture = native;
      if (capture == null || !capture.isRunning) {
        if (!_ended.isCompleted) _ended.complete();
      } else {
        unawaited(
          capture.ended.then(
            (_) {
              if (!_ended.isCompleted) _ended.complete();
            },
            onError: (Object _) {
              if (!_ended.isCompleted) _ended.complete();
            },
          ),
        );
      }
    }
    check();
  }

  @override
  Future<void> abort() async {
    _closing = true;
    _failure ??= const PlatformException(
      'TIMEOUT',
      'Chrome display recording was aborted',
    );
    unawaited(socket.close().catchError((Object _) {}));
    client.close(force: true);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(_failure!);
    }
    await native?.abort();
    // Do not wait indefinitely for native termination; ended retains ownership.
    unawaited(stop().catchError((Object _) {}));
  }
}
