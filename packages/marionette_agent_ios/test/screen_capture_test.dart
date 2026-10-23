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
import base64, json, os, pathlib, sys, time
root = pathlib.Path(__file__).parent
args = sys.argv[1:]
with (root / 'calls').open('a') as f: f.write(json.dumps(args) + '\n')
mode = (root / 'mode').read_text() if (root / 'mode').exists() else ''
if args[0] == '--find':
    if mode == 'sdk': sys.exit(1)
    print('/fixture/simctl')
elif args[1] == 'list':
    if mode == 'inventory': print('not json')
    else: print((root / 'inventory').read_text())
else:
    if mode == 'fail':
        print('PRIVATE OS ERROR', file=sys.stderr)
        sys.exit(1)
    if mode == 'stall':
        (root / 'pid').write_text(str(os.getpid()))
        time.sleep(60)
    sys.stdout.buffer.write(base64.b64decode('PNG'))
'''
          .replaceAll('PNG', png),
    );
    await Process.run('chmod', ['700', xcrun.path]);
    capture = IosScreenCapturer(xcrun: xcrun.path, isMacOS: true);
    await inventory([device(other), device(selected)]);
  });
  tearDown(() => root.delete(recursive: true));

  test('pins UDID among multiple booted devices and returns untouched PNG/provenance', () async {
    final result = await capture.capture(selected.toLowerCase(), deadline());
    expect(result.png, base64Decode(png));
    expect(result.metadata, containsPair('device', selected));
    expect(result.metadata, containsPair('runtime', runtime));
    expect(operations().last, [
      'simctl',
      'io',
      selected,
      'screenshot',
      '--type=png',
      '--display=internal',
      '--mask=ignored',
      '-',
    ]);
    expect(
      root.listSync().whereType<File>().map((f) => f.uri.pathSegments.last),
      unorderedEquals(['xcrun', 'calls', 'inventory']),
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
      expect(operations().any((args) => args.contains('screenshot')), isFalse);
    },
  );
  test('duplicate target inventory fails rather than choosing one', () async {
    await inventory([device(selected), device(selected)]);
    await expectLater(
      capture.capture(selected, deadline()),
      errorCode('AMBIGUOUS_TARGET'),
    );
    expect(operations().any((args) => args.contains('screenshot')), isFalse);
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
        operations().where((args) => args.contains('screenshot')),
        hasLength(1),
      );
    },
  );
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
      operations().where((args) => args.contains('screenshot')),
      hasLength(1),
    );
  });
}
