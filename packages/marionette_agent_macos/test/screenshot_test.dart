import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_macos/marionette_agent_macos.dart';
import 'package:marionette_agent_platform_interface/host_support.dart';
import 'package:test/test.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==';
void main() {
  late Directory root;
  late MacosScreenshotService service;
  late List<MacosDisplay> topology;
  late bool allowed;
  const primary = MacosDisplay(31, 0, 0, 0.5, 0.5, 1, 1, 0);
  const secondary = MacosDisplay(52, -10, 0, 1, 1, 1, 1, 0);
  Future<void> mode(String mode) =>
      File('${root.path}/mode').writeAsString(mode);
  Matcher error(String code) =>
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));
  Future<MacosScreenshot> capture([int display = 2, int ms = 5000]) =>
      service.capture(display, DateTime.now().add(Duration(milliseconds: ms)));
  List<List<dynamic>> calls() => File('${root.path}/calls').existsSync()
      ? File('${root.path}/calls')
            .readAsLinesSync()
            .map((s) => jsonDecode(s) as List)
            .toList()
      : [];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('macos-xctest-test-');
    allowed = true;
    topology = [primary, secondary];
    final exe = File('${root.path}/xcrun');
    await exe.writeAsString(
      r'''#!/usr/bin/python3
import base64,json,os,pathlib,plistlib,sys,time,shutil,subprocess
root=pathlib.Path(__file__).parent;args=sys.argv[1:]
with (root/'calls').open('a') as f:f.write(json.dumps(args)+'\n')
mode=(root/'mode').read_text() if (root/'mode').exists() else ''
if args[0]=='--find':
 if mode=='sdk':sys.exit(1)
 print('/fixture/xcodebuild')
elif args[:2]==['xcodebuild','build-for-testing']:
 if mode=='build':sys.exit(1)
 products=pathlib.Path(args[args.index('-derivedDataPath')+1])/'Build/Products';products.mkdir(parents=True)
 runner=products/'Debug/ScreenCapture-Runner.app/Contents/MacOS/ScreenCapture-Runner';runner.parent.mkdir(parents=True)
 shutil.copyfile('/bin/sleep',runner);runner.chmod(0o700)
 (products/'ScreenCapture.xctestrun').write_bytes(plistlib.dumps({'ScreenCapture':{'TestBundlePath':'__TESTROOT__/ScreenCapture.xctest'}}))
elif args[:2]==['xcodebuild','test-without-building']:
 plan=plistlib.loads(pathlib.Path(args[args.index('-xctestrun')+1]).read_bytes())
 assert plan['ScreenCapture']['EnvironmentVariables']['MRA_DISPLAY_INDEX'] in ['1','2']
 if mode=='test':print('PRIVATE LOG',file=sys.stderr);sys.exit(1)
 if mode=='stall':
  runner=pathlib.Path(args[args.index('-xctestrun')+1]).parent/'Debug/ScreenCapture-Runner.app/Contents/MacOS/ScreenCapture-Runner'
  child=subprocess.Popen([str(runner),'60']);(root/'runner-pid').write_text(str(child.pid))
  (root/'pid').write_text(str(os.getpid()));time.sleep(60)
 pathlib.Path(args[args.index('-resultBundlePath')+1]).mkdir()
elif args[:3]==['xcresulttool','export','attachments']:
 if mode=='export':sys.exit(1)
 out=pathlib.Path(args[args.index('--output-path')+1]);out.mkdir()
 attachment={'isAssociatedWithFailure':False,'suggestedHumanReadableName':'marionette-screen_0.png','exportedFileName':'../outside.png' if mode=='path' else 'screen.png'}
 records=[{'testIdentifier':'Capture/testCapture()','attachments':[attachment,attachment] if mode=='duplicate' else [attachment]}]
 (out/'manifest.json').write_text('bad' if mode=='manifest' else json.dumps(records))
 if mode=='symlink':(out/'screen.png').symlink_to(root/'calls')
 else:(out/'screen.png').write_bytes(b'bad' if mode=='png' else base64.b64decode('PNG'))
else:sys.exit(2)
'''
          .replaceAll('PNG', png),
    );
    await Process.run('chmod', ['700', exe.path]);
    service = MacosScreenshotService(
      xcrun: exe.path,
      temporaryRoot: root,
      permission: () => allowed,
      displays: () => topology,
    );
  });
  tearDown(() async {
    await service.dispose();
    expect(root.listSync().whereType<Directory>(), isEmpty);
    await root.delete(recursive: true);
  });
  test('XCTest selected display, untouched PNG, metadata, build reuse and serialization', () async {
    final shots = await Future.wait([capture(), capture(1)]);
    expect(shots[0].png, base64Decode(png));
    expect(shots[0].metadata, containsPair('source', 'macos-xcuiscreen'));
    expect(shots[0].metadata, containsPair('displayId', 52));
    expect(shots[1].metadata['scaleX'], 2);
    expect(calls().where((a) => a.contains('build-for-testing')), hasLength(1));
    expect(
      calls().where((a) => a.contains('test-without-building')),
      hasLength(2),
    );
    expect(calls().any((a) => a.join(' ').contains('screencapture')), isFalse);
  });
  test(
    'permission and missing/ambiguous screens fail before starting tools',
    () async {
      allowed = false;
      await expectLater(capture(), error('SCREEN_CAPTURE_PERMISSION_REQUIRED'));
      allowed = true;
      await expectLater(capture(3), error('TARGET_NOT_FOUND'));
      topology = [primary, secondary, secondary];
      await expectLater(capture(), error('UNSUPPORTED_CAPABILITY'));
      expect(calls(), isEmpty);
    },
  );
  test('expired or closed adapter starts no process', () async {
    await expectLater(capture(2, -1), error('TIMEOUT'));
    await service.dispose();
    await expectLater(capture(), error('IO_ERROR'));
    expect(calls(), isEmpty);
  });
  for (final failure in [
    'sdk',
    'build',
    'test',
    'export',
    'path',
    'duplicate',
    'manifest',
    'symlink',
    'png',
  ]) {
    test('$failure failure has no fallback and cleans staging', () async {
      await mode(failure);
      await expectLater(
        capture(),
        error(failure == 'sdk' ? 'UNSUPPORTED_CAPABILITY' : 'IO_ERROR'),
      );
      expect(
        calls().where((a) => a.contains('test-without-building')).length,
        lessThanOrEqualTo(1),
      );
    });
  }
  test('topology and permission changes discard capture', () async {
    var checks = 0;
    await service.dispose();
    service = MacosScreenshotService(
      xcrun: '${root.path}/xcrun',
      temporaryRoot: root,
      permission: () => allowed,
      displays: () => ++checks == 1 ? topology : topology.reversed.toList(),
    );
    await expectLater(capture(), error('TARGET_NOT_FOUND'));
    await service.dispose();
    checks = 0;
    service = MacosScreenshotService(
      xcrun: '${root.path}/xcrun',
      temporaryRoot: root,
      permission: () => ++checks == 1,
      displays: () => topology,
    );
    await expectLater(capture(), error('SCREEN_CAPTURE_PERMISSION_REQUIRED'));
  });
  test(
    'timeout terminates owned driver and queued expired work never starts',
    () async {
      await mode('stall');
      await expectLater(capture(2, 800), error('TIMEOUT'));
      final pidFile = File('${root.path}/pid');
      expect(pidFile.existsSync(), isTrue);
      final result = await Process.run('/bin/kill', [
        '-0',
        pidFile.readAsStringSync(),
      ]);
      expect(result.exitCode, isNot(0));
      final runnerPid = File('${root.path}/runner-pid').readAsStringSync();
      final status = await Process.run('/bin/ps', [
        '-p',
        runnerPid,
        '-o',
        'stat=',
      ]);
      expect(
        status.exitCode != 0 || (status.stdout as String).contains('Z'),
        isTrue,
        reason: 'Owned runner must stop even when its driver is interrupted',
      );
      await expectLater(capture(2, -1), error('TIMEOUT'));
      expect(
        calls().where((a) => a.contains('test-without-building')),
        hasLength(1),
      );
    },
  );
}
