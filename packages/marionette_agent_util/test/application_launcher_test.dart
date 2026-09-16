import 'dart:async';
import 'dart:io';

import 'package:marionette_agent_util/marionette_agent_util.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;
  late PlatformApplicationLauncher launcher;
  late String flutter;
  LaunchOptions options([Map<String, Object?> extra = const {}]) =>
      LaunchOptions.fromJson({
        'platform': 'tester',
        'project': project.path,
        'flutter': flutter,
        ...extra,
      });
  DateTime deadline([int seconds = 5]) =>
      DateTime.now().add(Duration(seconds: seconds));
  Future<void> script(String body) async {
    await File(flutter).writeAsString('#!/bin/sh\n$body\n');
    await Process.run('chmod', ['700', flutter]);
  }

  setUp(() async {
    project = await Directory.systemTemp.createTemp('launcher-test-');
    await Directory('${project.path}/lib').create();
    await Directory('${project.path}/.dart_tool').create();
    await File('${project.path}/lib/main.dart').writeAsString('void main() {}');
    await File('${project.path}/pubspec.yaml').writeAsString('name: fixture');
    flutter = '${project.path}/flutter';
    launcher = PlatformApplicationLauncher();
  });
  tearDown(() async {
    await launcher.dispose();
    await project.delete(recursive: true);
  });
  const ready = r'''
for arg; do
  case "$arg" in --vmservice-out-file=*) uri="${arg#*=}";; esac
done
printf '%s\n' '[{"event":"app.start","params":{"appId":"owned-test"}}]'
printf '%s' 'http://127.0.0.1:12345/private-token/' > "$uri"
printf '%s\n' '[{"event":"app.started","params":{"appId":"owned-test"}}]'
printf '%s' "$$" > child-pid
while IFS= read -r message; do
  case "$message" in *app.stop*) exit 0;; esac
done
''';
  test(
    'Web waits for app.started even when its URI file is already present',
    () async {
      await script(
        ready.replaceFirst(
          "printf '%s\\n' '[{\"event\":\"app.started\"",
          "sleep 1\ntouch flutter-ready\nprintf '%s\\n' '[{\"event\":\"app.started\"",
        ),
      );
      final app = await launcher.start(
        options({'platform': 'web'}),
        deadline(),
      );
      try {
        expect(File('${project.path}/flutter-ready').existsSync(), isTrue);
      } finally {
        await app.stop();
      }
    },
  );
  test('returns a local URI, locks project, stops only owned process, and removes secrets', () async {
    await script(ready);
    final app = await launcher.start(options(), deadline());
    expect(app.uri.port, 12345);
    expect(app.description['platform'], 'tester');
    expect(app.description.toString(), isNot(contains('private-token')));
    await expectLater(
      launcher.start(options(), deadline()),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'SESSION_CONFLICT',
        ),
      ),
    );
    await Future.wait([app.stop(), app.stop()]);
    expect(await app.exited, 0);
    expect(app.description['state'], 'exited');
    final next = await launcher.start(options(), deadline());
    await next.stop();
  });
  test(
    'startup failure has no child logs or credentials in the error',
    () async {
      await script('echo http://localhost:12345/secret-token/ >&2\nexit 7');
      await expectLater(
        launcher.start(options(), deadline()),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'CONNECTION_LOST')
              .having(
                (e) => e.toString(),
                'safe message',
                isNot(contains('secret-token')),
              ),
        ),
      );
    },
  );
  test(
    'missing executable maps to capability error before readiness',
    () async {
      await expectLater(
        launcher.start(options(), deadline()),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_CAPABILITY',
          ),
        ),
      );
    },
  );
  test('deadline stops child and allows another run', () async {
    await script(
      'trap "exit 0" INT TERM\nprintf "%s" "\$\$" > child-pid\nwhile :; do sleep 0.1; done',
    );
    await expectLater(
      launcher.start(options(), deadline(1)),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'TIMEOUT'),
      ),
    );
    final pid = int.parse(
      await File('${project.path}/child-pid').readAsString(),
    );
    expect(Process.killPid(pid, ProcessSignal.sigcont), isFalse);
    await script(ready);
    await (await launcher.start(options(), deadline())).stop();
  });
  test('disposing during startup cancels the owned runner', () async {
    await script(
      'trap "exit 0" INT TERM\nprintf "%s" "\$\$" > child-pid\nwhile :; do sleep 0.1; done',
    );
    final start = launcher.start(options(), deadline(20));
    final failure = expectLater(
      start,
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'CONNECTION_LOST',
        ),
      ),
    );
    while (!await File('${project.path}/child-pid').exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await launcher.dispose();
    await failure;
    final pid = int.parse(
      await File('${project.path}/child-pid').readAsString(),
    );
    expect(Process.killPid(pid, ProcessSignal.sigcont), isFalse);
  });
  test(
    'native options reject wrong-platform fields and occupied Android ports',
    () async {
      for (final extra in [
        {'platform': 'tester', 'avd': 'x'},
        {'platform': 'android', 'avd': 'x', 'port': 5555},
        {'platform': 'ios'},
        {'platform': 'web', 'runtime': 'x'},
        {'unknown': true},
      ]) {
        expect(() => options(extra), throwsA(isA<PlatformException>()));
      }
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        5682,
      );
      try {
        await expectLater(
          launcher.start(
            options({'platform': 'android', 'avd': 'unused', 'port': 5682}),
            deadline(),
          ),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'SESSION_CONFLICT',
            ),
          ),
        );
      } finally {
        await socket.close();
      }
    },
  );
  test('tester, web, macOS select native runner flags without shell interpolation', () async {
    await script(
      'printf "%s\\n" "\$@" > args\nprintf "%s" "\$MARIONETTE_HEADLESS" > headless\n$ready',
    );
    for (final platform in ['tester', 'web', 'macos']) {
      final app = await launcher.start(
        options({'platform': platform}),
        deadline(),
      );
      final args = await File('${project.path}/args').readAsLines();
      expect(
        args,
        contains(switch (platform) {
          'tester' => 'flutter-tester',
          'web' => 'chrome',
          _ => 'macos',
        }),
      );
      expect(args.contains('--web-run-headless'), platform == 'web');
      expect(
        args.contains('--dart-define=MARIONETTE_HEADLESS=true'),
        platform == 'macos',
      );
      if (platform == 'macos') {
        expect(await File('${project.path}/headless').readAsString(), '1');
      }
      await app.stop();
    }
  });
  test(
    'Android waits for its shell after adb first reports a device',
    () async {
      final emulatorPath = '${project.path}/emulator';
      final adbPath = '${project.path}/adb';
      await File(emulatorPath).writeAsString(r'''#!/bin/sh
trap 'exit 0' INT TERM
touch emulator-started
while :; do sleep 0.1; done
''');
      await File(adbPath).writeAsString(r'''#!/bin/sh
if [ "$1" = devices ]; then
  if [ -f emulator-started ]; then printf 'emulator-5680\tdevice\n'; fi
  exit 0
fi
if [ ! -f polled ]; then touch polled; exit 1; fi
printf '1\n'
''');
      for (final executable in [emulatorPath, adbPath]) {
        await Process.run('chmod', ['700', executable]);
      }
      await script(ready);
      launcher = PlatformApplicationLauncher(
        emulator: emulatorPath,
        adb: adbPath,
      );
      final app = await launcher.start(
        options({'platform': 'android', 'avd': 'fixture', 'port': 5680}),
        deadline(),
      );
      expect(await File('${project.path}/polled').exists(), isTrue);
      expect(app.description['device'], 'emulator-5680');
      await app.stop();
    },
  );
}
