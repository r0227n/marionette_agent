import 'dart:async';
import 'dart:convert';

import 'package:marionette_agent_util/marionette_agent_util.dart';

import '../protocol/protocol.dart';
import 'backend.dart';

/// Recording owns a separate read-only connection; stopping never releases
/// keyboard state or invalidates the command session's refs.
class FlutterScreenRecorder implements ScreenRecorder {
  FlutterScreenRecorder(this.backend, this.uri);
  final ScreenshotConnectionBackend backend;
  final Uri uri;

  @override
  Future<RecordingHandle> start(
    RecordingTarget target,
    String stagingPath,
    DateTime deadline,
  ) async {
    var expired = false;
    final opening = backend.openScreenshotConnection(uri);
    unawaited(
      opening
          .then((value) async {
            if (expired) await value.close();
          }, onError: (Object _) {})
          .catchError((Object _) {}),
    );
    try {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) throw TimeoutException('Capture startup');
      final feed = await opening.timeout(remaining);
      return await PngScreenRecorder(
        capture: () async {
          try {
            final images = await feed.capture();
            if (images.length != 1) {
              throw const PlatformException(
                'UNSUPPORTED_CAPABILITY',
                'Flutter recording requires exactly one view',
              );
            }
            return base64Decode(images.single);
          } on AgentError catch (error) {
            throw PlatformException(
              error.code,
              'Application image capture failed',
            );
          } on FormatException {
            throw const PlatformException(
              'IO_ERROR',
              'Invalid application PNG',
            );
          }
        },
        close: feed.close,
      ).start(target, stagingPath, deadline);
    } on TimeoutException {
      throw const PlatformException(
        'TIMEOUT',
        'Application recording startup expired',
      );
    } on AgentError catch (error) {
      throw PlatformException(
        error.code,
        'Cannot connect application recording',
      );
    } finally {
      expired = true;
      // Once start succeeds the handle owns the connection. Failed starts are
      // closed by PngScreenRecorder; connection establishment failures close
      // within the adapter, including late completion via the handler above.
    }
  }
}
