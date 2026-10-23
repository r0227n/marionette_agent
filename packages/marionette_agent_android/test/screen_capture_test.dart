import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File script, calls;
  late AndroidScreenCapturer capturer;
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 5));
  Matcher fails(String code, [String? message]) => throwsA(
    isA<PlatformException>()
        .having((e) => e.code, 'code', code)
        .having(
          (e) => e.message,
          'message',
          message == null ? anything : contains(message),
        ),
  );
  Future<void> fixture({
    String state = 'device',
    String displays = 'mDisplayId=0',
    bool physical = false,
    String capture = 'printf PNG',
    bool hang = false,
    bool duplicate = false,
  }) async {
    await script.writeAsString('''#!/bin/sh
printf '%s\\n' "\$*" >> '${calls.path}'
case "\$*" in
  'devices -l') printf 'List of devices attached\\nemulator-5660 $state\\nemulator-5662 device\\n${duplicate ? 'emulator-5660 device\\n' : ''}';;
  '-s emulator-5660 shell getprop ro.kernel.qemu') printf '${physical ? '0' : '1'}';;
  '-s emulator-5660 shell dumpsys display') printf '$displays';;
  '-s emulator-5660 exec-out screencap -p') ${hang ? 'exec sleep 20' : capture};;
  *) exit 91;;
esac
''');
    await Process.run('chmod', ['700', script.path]);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('adb-capture-');
    script = File('${directory.path}/adb');
    calls = File('${directory.path}/calls');
    capturer = AndroidScreenCapturer(adb: script.path);
    await fixture();
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'explicit serial remains fixed with multiple connected devices',
    () async {
      final result = await capturer.capture('emulator-5660', deadline());
      expect(utf8.decode(result.png), 'PNG');
      expect(result.source, 'android-adb');
      expect(result.display, 0);
      expect(await calls.readAsLines(), [
        'devices -l',
        '-s emulator-5660 shell getprop ro.kernel.qemu',
        '-s emulator-5660 shell dumpsys display',
        '-s emulator-5660 exec-out screencap -p',
      ]);
    },
  );
  for (final row in [
    ('unauthorized', 'IO_ERROR'),
    ('offline', 'CONNECTION_LOST'),
    ('recovery', 'UNSUPPORTED_CAPABILITY'),
  ]) {
    test('rejects ${row.$1} without capture', () async {
      await fixture(state: row.$1);
      await expectLater(
        capturer.capture('emulator-5660', deadline()),
        fails(row.$2),
      );
      expect(await calls.readAsLines(), ['devices -l']);
    });
  }
  test(
    'unknown, malformed and duplicate serials cannot select another device',
    () async {
      await expectLater(
        capturer.capture('missing', deadline()),
        fails('INVALID_ARGUMENT'),
      );
      await expectLater(
        capturer.capture('-s other', deadline()),
        fails('INVALID_ARGUMENT'),
      );
      await fixture(duplicate: true);
      await expectLater(
        capturer.capture('emulator-5660', deadline()),
        fails('INVALID_ARGUMENT'),
      );
      expect(await calls.readAsString(), isNot(contains('screencap')));
    },
  );
  test('unsupported physical hardware is rejected', () async {
    await fixture(physical: true);
    await expectLater(
      capturer.capture('emulator-5660', deadline()),
      fails('UNSUPPORTED_CAPABILITY', 'Emulator'),
    );
  });
  test(
    'unknown topology and secondary displays are rejected before capture',
    () async {
      for (final topology in ['', 'mDisplayId=0\\nmDisplayId=2']) {
        await fixture(displays: topology);
        await expectLater(
          capturer.capture('emulator-5660', deadline()),
          fails('UNSUPPORTED_CAPABILITY', 'display'),
        );
      }
      expect(await calls.readAsString(), isNot(contains('screencap')));
    },
  );
  test('missing adb has a specific installation failure', () async {
    await expectLater(
      AndroidScreenCapturer(adb: '${directory.path}/missing')
          .capture('emulator-5660', deadline()),
      fails('UNSUPPORTED_CAPABILITY', 'adb'),
    );
  });
  test('capture deadline kills owned client without replay', () async {
    await fixture(hang: true);
    final watch = Stopwatch()..start();
    await expectLater(
      capturer.capture(
        'emulator-5660',
        DateTime.now().add(const Duration(seconds: 2)),
      ),
      fails('TIMEOUT'),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(
      (await calls.readAsLines()).where((line) => line.contains('screencap')),
      hasLength(1),
    );
  });
  test(
    'known permission denial is reported without exposing raw stderr',
    () async {
      await fixture(capture: 'echo "Permission denied secret" >&2; exit 1');
      await expectLater(
        capturer.capture('emulator-5660', deadline()),
        fails('IO_ERROR', 'denied'),
      );
    },
  );
}
