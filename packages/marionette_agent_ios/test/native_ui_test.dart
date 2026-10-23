import 'dart:convert';
import 'dart:typed_data';

import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_platform_interface/host_support.dart';
import 'package:test/test.dart';

void main() {
  test('decodes idb flat accessibility output including null attributes', () {
    final nodes = decodeIosNativeElements(
      jsonEncode([
        {
          'type': 'Button',
          'AXLabel': 'Allow',
          'AXUniqueId': null,
          'AXValue': null,
          'enabled': true,
          'frame': {'x': 10, 'y': 20.5, 'width': 100, 'height': 40},
        },
      ]),
    );
    expect(nodes.single.text, 'Allow');
    expect(nodes.single.identifier, isNull);
    expect(nodes.single.bounds.y, 20.5);
    expect(nodes.single.tappable, isTrue);
    expect(
      () => decodeIosNativeElements('[{}]'),
      throwsA(isA<PlatformException>()),
    );
  });
  test(
    'passes explicit UDID and integer points accepted by idb 1.1.7',
    () async {
      final calls = <List<String>>[];
      final backend = IosNativeUi(
        run: (command, args, deadline) async {
          calls.add([command, ...args]);
          return Uint8List.fromList(utf8.encode('[]'));
        },
      );
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      const device = '00000000-0000-0000-0000-000000000001';
      await backend.inspect(device, deadline);
      await backend.tap(device, 200.5, 552.6, deadline);
      await backend.swipe(device, 1.2, 20.5, 200.8, 30.1, deadline);
      await backend.screenshot(device, deadline);
      expect(calls, [
        ['idb', 'ui', 'describe-all', '--udid', device, '--json'],
        ['idb', 'ui', 'tap', '--udid', device, '201', '553'],
        [
          'idb',
          'ui',
          'swipe',
          '--udid',
          device,
          '1',
          '21',
          '201',
          '30',
          '--duration',
          '0.3',
        ],
        ['xcrun', 'simctl', 'io', device, 'screenshot', '--type=png', '-'],
      ]);
    },
  );
}
