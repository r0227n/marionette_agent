import 'dart:io';

import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_platform_interface/host_support.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;
  late ManagedApplication app;
  late IosApplicationBackend backend;
  late File actions;

  setUp(() async {
    project = await Directory.systemTemp.createTemp('ios-backend-test-');
    final bundle = Directory(
      '${project.path}/build/ios/iphonesimulator/Test.app',
    );
    await bundle.create(recursive: true);
    await File('${bundle.path}/Info.plist').writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.owned</string></dict></plist>
''');
    final flutter = File('${project.path}/flutter');
    await flutter.writeAsString('#!/bin/sh\nexit 0\n');
    final xcrun = File('${project.path}/xcrun');
    actions = File('${project.path}/actions');
    await xcrun.writeAsString(
      r'''#!/bin/sh
printf '%s\n' "$4" >> "ACTIONS"
case "$4" in
  create) printf '%s\n' '11111111-2222-3333-4444-555555555555';;
  install) if [ -f "FAIL" ]; then exit 7; fi;;
  launch)
    printf '%s\n' 'Dart VM service is listening on http://127.0.0.1:12345/private-token/'
    trap 'exit 0' INT TERM
    while :; do sleep 0.1; done;;
esac
'''
          .replaceAll('ACTIONS', actions.path)
          .replaceAll('FAIL', '${project.path}/fail'),
    );
    for (final file in [flutter, xcrun]) {
      await Process.run('chmod', ['700', file.path]);
    }
    backend = IosApplicationBackend(xcrun: xcrun.path);
    app = ManagedApplication(
      LaunchOptions.fromJson({
        'platform': 'ios',
        'project': project.path,
        'flutter': flutter.path,
        'deviceType': 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro',
        'runtime': 'com.apple.CoreSimulator.SimRuntime.iOS-26-2',
      }),
      await Directory.systemTemp.createTemp('ios-backend-owned-'),
    );
  });
  tearDown(() async {
    await app.stop();
    await project.delete(recursive: true);
  });

  test(
    'private simulator launch preserves URI and cleans up only its device',
    () async {
      await backend.start(app, DateTime.now().add(const Duration(seconds: 10)));
      expect(app.uri.port, 12345);
      expect(app.description.toString(), isNot(contains('private-token')));
      await app.stop();
      expect(app.runner!.running, isFalse);
      expect(await app.root.exists(), isFalse);
      expect(
        (await actions.readAsLines())
            .where((action) => action != 'spawn')
            .toList(),
        [
          'create',
          'boot',
          'bootstatus',
          'install',
          'launch',
          'shutdown',
          'delete',
        ],
      );
    },
  );

  test('failure after device creation retains cleanup ownership', () async {
    await File('${project.path}/fail').create();
    await expectLater(
      backend.start(app, DateTime.now().add(const Duration(seconds: 10))),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR'),
      ),
    );
    await app.stop();
    expect(
      (await actions.readAsLines())
          .where((action) => action != 'spawn')
          .toList(),
      ['create', 'boot', 'bootstatus', 'install', 'shutdown', 'delete'],
    );
    expect(await app.root.exists(), isFalse);
  });
}
