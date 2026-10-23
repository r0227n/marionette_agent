import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_macos/marionette_agent_macos.dart';
import 'package:marionette_agent_platform_interface/host_support.dart';
import 'package:test/test.dart';

class CaptureProcess implements Process {
  CaptureProcess({bool hang = false, int code = 0}) {
    if (!hang) ended.complete(code);
  }
  final ended = Completer<int>();
  final signals = <ProcessSignal>[];
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => ended.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (!ended.isCompleted) ended.complete(-9);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==',
  );
  const primary = MacosDisplay(31, 0, 0, 0.5, 0.5, 1, 1, 0);
  const secondary = MacosDisplay(52, -10, 0, 1, 1, 1, 1, 0);
  late List<MacosDisplay> topology;
  late bool allowed;
  late int captures;
  String? staging;
  CaptureProcess? process;
  Future<Process> start(String exe, List<String> args) async {
    captures++;
    expect(exe, '/usr/sbin/screencapture');
    expect(args.take(5), ['-x', '-t', 'png', '-D', '2']);
    staging = File(args.last).parent.path;
    await File(args.last).writeAsBytes(png);
    return process ??= CaptureProcess();
  }

  MacosScreenshotService service({CaptureProcessStarter? starter}) =>
      MacosScreenshotService(
        permission: () => allowed,
        displays: () => topology,
        start: starter ?? start,
      );
  Future<MacosScreenshot> capture(
    MacosScreenshotService service, [
    int ms = 2000,
  ]) => service.capture(2, DateTime.now().add(Duration(milliseconds: ms)));
  Matcher error(String code) =>
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));
  setUp(() {
    topology = [primary, secondary];
    allowed = true;
    captures = 0;
    staging = null;
    process = null;
  });
  tearDown(() {
    if (staging != null) expect(Directory(staging!).existsSync(), false);
  });
  test(
    'explicit secondary display, native pixels and no recording lifecycle',
    () async {
      final shot = await capture(service());
      expect(shot.png, png);
      expect(shot.metadata, containsPair('displayId', 52));
      expect(shot.metadata, containsPair('displayIndex', 2));
      expect(shot.metadata, containsPair('pixelWidth', 1));
      expect(shot.metadata, containsPair('scaleX', 1.0));
      expect(captures, 1);
    },
  );
  test(
    'Retina scale derives from actual PNG and selected display bounds',
    () async {
      topology = [secondary, primary];
      final shot = await capture(service());
      expect(shot.metadata['scaleX'], 2.0);
      expect(shot.metadata['displayId'], 31);
    },
  );
  for (final state in ['unrequested', 'denied']) {
    test(
      '$state preflight refuses capture without requesting permission',
      () async {
        allowed = false;
        await expectLater(
          capture(service()),
          error('SCREEN_CAPTURE_PERMISSION_REQUIRED'),
        );
        expect(captures, 0);
      },
    );
  }
  test('missing display never defaults to main', () async {
    topology = [primary];
    await expectLater(capture(service()), error('TARGET_NOT_FOUND'));
    expect(captures, 0);
  });
  test(
    'reordering or moving a display during capture discards image',
    () async {
      await expectLater(
        capture(
          service(
            starter: (exe, args) async {
              final p = await start(exe, args);
              topology = [secondary, primary];
              return p;
            },
          ),
        ),
        error('TARGET_NOT_FOUND'),
      );
      expect(captures, 1);
    },
  );
  test('permission revoked during capture never publishes pixels', () async {
    await expectLater(
      capture(
        service(
          starter: (exe, args) async {
            final p = await start(exe, args);
            allowed = false;
            return p;
          },
        ),
      ),
      error('SCREEN_CAPTURE_PERMISSION_REQUIRED'),
    );
  });
  test('native failure does not retry or substitute an image', () async {
    process = CaptureProcess(code: 1);
    await expectLater(capture(service()), error('IO_ERROR'));
    expect(captures, 1);
  });
  test('timeout kills/reaps child then removes staging', () async {
    process = CaptureProcess(hang: true);
    await expectLater(capture(service(), 100), error('TIMEOUT'));
    expect(process!.signals, contains(ProcessSignal.sigkill));
    expect(captures, 1);
  });
  test('expired request does not launch', () async {
    await expectLater(capture(service(), -1), error('TIMEOUT'));
    expect(captures, 0);
  });
  test('invalid PNG and missing files are acquisition failures', () async {
    for (final bytes in [
      <int>[],
      [1, 2, 3],
    ]) {
      await expectLater(
        capture(
          service(
            starter: (exe, args) async {
              final p = await start(exe, args);
              await File(args.last).writeAsBytes(bytes);
              return p;
            },
          ),
        ),
        error('IO_ERROR'),
      );
    }
  });
}
