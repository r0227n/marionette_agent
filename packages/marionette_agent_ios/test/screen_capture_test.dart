import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
import 'package:test/test.dart';

const selected = '11111111-2222-3333-4444-555555555555';
const other = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';
const runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-26-2';
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0ioAAAAASUVORK5CYII=';
Matcher errorCode(String code) =>
    throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

void main() {
  late Directory root;
  late IosScreenCapturer capture;
  late File calls;
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 5));
  Map<String, Object> device(String id, [String state = 'Booted']) => {
    'udid': id,
    'state': state,
    'isAvailable': true,
  };
  Future<void> inventory(List<Object> devices, {String os = runtime}) async {
    await File('${root.path}/inventory').writeAsString(
      jsonEncode({
        'devices': {os: devices},
      }),
    );
  }

  Future<void> mode(String value) async {
    await File('${root.path}/mode').writeAsString(value);
  }

  List<List<String>> operations() => calls
      .readAsLinesSync()
      .map((line) => (jsonDecode(line) as List).cast<String>())
      .toList();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('native-capture-test-');
    calls = File('${root.path}/calls');
    final xcrun = File('${root.path}/xcrun');
    await xcrun.writeAsString(
      r'''#!/usr/bin/python3
import base64,json,os,pathlib,plistlib,socket,sys,time
root=pathlib.Path(__file__).parent
args=sys.argv[1:]
with (root/'calls').open('a') as f:f.write(json.dumps(args)+'\n')
mode=(root/'mode').read_text() if (root/'mode').exists() else ''
if args[0]=='--find':
    if mode=='sdk':sys.exit(1)
    print('/fixture/xcodebuild')
elif args[:2]==['simctl','list']:
    print('invalid' if mode=='inventory' else (root/'inventory').read_text())
elif args[0]=='simctl':pass
elif args[:2]==['xcodebuild','build-for-testing']:
    if mode=='build-fail':print('PRIVATE BUILD',file=sys.stderr);sys.exit(1)
    products=pathlib.Path(args[args.index('-derivedDataPath')+1])/'Build/Products'
    products.mkdir(parents=True);(products/'ScreenCapture.xctestrun').write_bytes(plistlib.dumps({'ScreenCapture':{'TestBundlePath':'fixture'}}))
elif args[:2]==['xcodebuild','test-without-building']:
    if mode=='fail':print('PRIVATE TEST',file=sys.stderr);sys.exit(1)
    if mode=='stall':(root/'pid').write_text(str(os.getpid()));time.sleep(60)
    if '-only-testing:ScreenCapture/Capture/testStream' in args:
        (root/'pid').write_text(str(os.getpid()))
        plan=plistlib.loads(pathlib.Path(args[args.index('-xctestrun')+1]).read_bytes())
        env=plan['ScreenCapture']['EnvironmentVariables']
        server=socket.socket();server.bind(('127.0.0.1',int(env['MRA_RECORD_PORT'])));server.listen(2)
        frame=0
        while True:
            conn,_=server.accept()
            with conn:
                request=conn.makefile('rb').readline().strip().decode()
                if request!=env['MRA_RECORD_TOKEN']:continue
                frame+=1
                conn.sendall(base64.b64decode('PNG') if frame==1 else b'invalid frame')
    pathlib.Path(args[args.index('-resultBundlePath')+1]).mkdir()
elif args[:3]==['xcresulttool','export','attachments']:
    if mode=='export-fail':sys.exit(1)
    output=pathlib.Path(args[args.index('--output-path')+1]);output.mkdir()
    name='../outside.png' if mode=='bad-name' else 'screen.png'
    attachment={'deviceId':'OTHER' if mode=='wrong-device' else '11111111-2222-3333-4444-555555555555','isAssociatedWithFailure':False,'suggestedHumanReadableName':'marionette-screen_0.png','exportedFileName':name}
    record={'testIdentifier':'Capture/testCapture()','attachments':[attachment,attachment] if mode=='duplicate' else [attachment]}
    (output/'manifest.json').write_text('invalid' if mode=='manifest' else json.dumps([record]))
    if mode=='symlink':(output/'screen.png').symlink_to(root/'inventory')
    else:(output/'screen.png').write_bytes(base64.b64decode('PNG'))
else:sys.exit(2)
'''
          .replaceAll('PNG', png),
    );
    await Process.run('chmod', ['700', xcrun.path]);
    await Directory('${root.path}/owned').create();
    capture = IosScreenCapturer(
      xcrun: xcrun.path,
      isMacOS: true,
      temporaryRoot: Directory('${root.path}/owned'),
    );
    await inventory([device(other), device(selected)]);
  });
  tearDown(() async {
    await capture.dispose();
    await root.delete(recursive: true);
  });

  test(
    'failed recording frames terminate the owned runner without explicit stop',
    () async {
      final recording = await capture.record(
        const RecordingTarget(RecordingPlatform.ios, selected, fps: 10),
        '${root.path}/capture.mp4',
        DateTime.now().add(const Duration(seconds: 10)),
      );
      try {
        await recording.ended.timeout(const Duration(seconds: 10));
        expect(recording.isRunning, isFalse);
        await expectLater(recording.stop(), errorCode('IO_ERROR'));
        final child = int.parse(await File('${root.path}/pid').readAsString());
        expect(Process.killPid(child, ProcessSignal.sigcont), isFalse);
        expect(await File('${root.path}/capture.mp4').exists(), isFalse);
        expect(
          operations().where((args) => args.contains('test-without-building')),
          hasLength(1),
        );
      } finally {
        await recording.abort();
      }
    },
  );

  test('pins UDID among multiple booted devices and returns untouched PNG/provenance', () async {
    final result = await capture.capture(selected.toLowerCase(), deadline());
    expect(result.png, base64Decode(png));
    expect(result.metadata, containsPair('device', selected));
    expect(result.metadata, containsPair('runtime', runtime));
    final calls = operations();
    expect(
      calls.where((args) => args.contains('test-without-building')).single,
      contains('platform=iOS Simulator,id=$selected'),
    );
    expect(
      calls.any((args) => args.contains('screenshot') || args.contains('io')),
      isFalse,
    );
    expect(result.metadata, containsPair('method', 'xcuiscreen'));
    await capture.capture(selected, deadline());
    expect(
      operations().where((args) => args.contains('build-for-testing')),
      hasLength(1),
    );
    expect(
      operations().where((args) => args.contains('test-without-building')),
      hasLength(2),
    );
    expect(
      Directory('${root.path}/owned')
          .listSync(recursive: true)
          .any((e) => e.path.endsWith('.png') || e.path.endsWith('.xcresult')),
      isFalse,
    );
  });
  test(
    'rejects aliases and missing target without starting any process',
    () async {
      for (final id in ['', 'booted', 'iPhone 17 Pro', '--help']) {
        await expectLater(
          capture.capture(id, deadline()),
          errorCode('INVALID_ARGUMENT'),
        );
      }
      expect(await calls.exists(), isFalse);
    },
  );
  test(
    'unavailable, stopped, and non-iOS targets are never captured',
    () async {
      for (final devices in [
        [device(other)],
        [device(selected, 'Shutdown')],
        [
          {...device(selected), 'isAvailable': false},
        ],
      ]) {
        await inventory(devices);
        await expectLater(
          capture.capture(selected, deadline()),
          errorCode('UNRESOLVABLE_TARGET'),
        );
      }
      await inventory([
        device(selected),
      ], os: 'com.apple.CoreSimulator.SimRuntime.tvOS-26-2');
      await expectLater(
        capture.capture(selected, deadline()),
        errorCode('UNRESOLVABLE_TARGET'),
      );
      expect(
        operations().any((args) => args.contains('test-without-building')),
        isFalse,
      );
    },
  );
  test('duplicate target inventory fails rather than choosing one', () async {
    await inventory([device(selected), device(selected)]);
    await expectLater(
      capture.capture(selected, deadline()),
      errorCode('AMBIGUOUS_TARGET'),
    );
    expect(
      operations().any((args) => args.contains('test-without-building')),
      isFalse,
    );
  });
  test(
    'missing SDK, malformed inventory, and capture failure are structured',
    () async {
      for (final entry in {
        'sdk': 'UNSUPPORTED_CAPABILITY',
        'inventory': 'IO_ERROR',
        'fail': 'IO_ERROR',
      }.entries) {
        await mode(entry.key);
        await expectLater(
          capture.capture(selected, deadline()),
          errorCode(entry.value),
        );
      }
      await expectLater(
        IosScreenCapturer(
          xcrun: '${root.path}/absent',
          isMacOS: true,
        ).capture(selected, deadline()),
        errorCode('UNSUPPORTED_CAPABILITY'),
      );
      await expectLater(
        IosScreenCapturer(isMacOS: false).capture(selected, deadline()),
        errorCode('UNSUPPORTED_CAPABILITY'),
      );
      expect(
        operations().where((args) => args.contains('test-without-building')),
        hasLength(1),
      );
    },
  );
  test('foreign, duplicate and malformed attachments never succeed and staging is removed', () async {
    for (final state in [
      'export-fail',
      'manifest',
      'wrong-device',
      'duplicate',
      'bad-name',
      'symlink',
    ]) {
      await mode(state);
      await expectLater(
        capture.capture(selected, deadline()),
        errorCode('IO_ERROR'),
      );
      expect(
        Directory('${root.path}/owned')
            .listSync(recursive: true)
            .any((e) => e.path.endsWith('.xcresult')),
        isFalse,
      );
    }
  });
  test('timeout kills the owned capture process without retry', () async {
    await mode('stall');
    await expectLater(
      capture.capture(selected, DateTime.now().add(const Duration(seconds: 1))),
      errorCode('TIMEOUT'),
    );
    final child = int.parse(await File('${root.path}/pid').readAsString());
    for (var i = 0; i < 50; i++) {
      if (!Process.killPid(child, ProcessSignal.sigcont)) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(Process.killPid(child, ProcessSignal.sigcont), isFalse);
    expect(
      operations().where((args) => args.contains('test-without-building')),
      hasLength(1),
    );
  });
  test('expired queued capture starts no process', () async {
    await mode('stall');
    await Future.wait([
      expectLater(
        capture.capture(
          selected,
          DateTime.now().add(const Duration(seconds: 1)),
        ),
        errorCode('TIMEOUT'),
      ),
      expectLater(
        capture.capture(
          selected,
          DateTime.now().add(const Duration(milliseconds: 100)),
        ),
        errorCode('TIMEOUT'),
      ),
    ]);
    expect(
      operations().where((args) => args.contains('test-without-building')),
      hasLength(1),
    );
    expect(operations().where((args) => args.contains('--find')), hasLength(1));
  });
}
