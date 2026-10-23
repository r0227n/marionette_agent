import 'dart:convert';
import 'dart:typed_data';

import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_platform_interface/host_support.dart';
import 'package:test/test.dart';

const hierarchy = '''<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<hierarchy rotation="0"><node text="Allow &amp; continue" resource-id="permission_allow"
class="android.widget.Button" package="com.android.permissioncontroller"
content-desc="" enabled="true" bounds="[20,30][200,90]">
<node text="" resource-id="" class="android.widget.ImageView" content-desc="Photo taken yesterday"
enabled="true" bounds="[0,90][100,190]" /></node></hierarchy>
UI hierchary dumped to: /dev/tty''';

void main() {
  test(
    'parses nested hierarchy, XML entities, content descriptions and bounds',
    () {
      final nodes = decodeAndroidNativeElements(hierarchy);
      expect(nodes, hasLength(2));
      expect(nodes[0].text, 'Allow & continue');
      expect(nodes[0].identifier, 'permission_allow');
      expect(nodes[0].package, 'com.android.permissioncontroller');
      expect(nodes[0].bounds.toJson(), {
        'x': 20.0,
        'y': 30.0,
        'width': 180.0,
        'height': 60.0,
      });
      expect(nodes[1].text, 'Photo taken yesterday');
      expect(nodes[1].identifier, isNull);
      for (final invalid in [
        'ERROR: could not get idle state',
        hierarchy.replaceFirst('[20,30][200,90]', 'unknown'),
      ]) {
        expect(
          () => decodeAndroidNativeElements(invalid),
          throwsA(isA<PlatformException>()),
        );
      }
    },
  );
  test(
    'every adb invocation selects serial and no shared dump file is used',
    () async {
      final calls = <List<String>>[];
      final backend = AndroidNativeUi(
        run: (command, args, deadline) async {
          calls.add([command, ...args]);
          return Uint8List.fromList(utf8.encode(hierarchy));
        },
      );
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      await backend.inspect('emulator-5554', deadline);
      await backend.tap('emulator-5554', 20.8, 40.2, deadline);
      await backend.swipe('emulator-5554', 20, 40, 20, 300, deadline);
      await backend.screenshot('emulator-5554', deadline);
      expect(
        calls.every((call) => call.take(3).join(' ') == 'adb -s emulator-5554'),
        isTrue,
      );
      expect(calls[0].skip(3), ['exec-out', 'uiautomator', 'dump', '/dev/tty']);
      expect(calls[1].skip(3), ['shell', 'input', 'tap', '21', '40']);
      expect(calls[2].skip(3), [
        'shell',
        'input',
        'swipe',
        '20',
        '40',
        '20',
        '300',
        '300',
      ]);
      expect(calls[3].skip(3), ['exec-out', 'screencap', '-p']);
    },
  );
}
