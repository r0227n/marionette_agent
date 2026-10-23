import 'package:marionette_agent_platform_interface/host_support.dart';

Future<List<Map<String, Object?>>> listAndroidDevices(DateTime deadline) async {
  final text = await readDeviceInventory('adb', ['devices', '-l'], deadline);
  return [
    for (final line in text.split('\n').skip(1))
      if (RegExp(r'^\S+\s+device(?:\s|$)').hasMatch(line))
        {
          'platform': 'android',
          'id': line.split(RegExp(r'\s+')).first,
          'state': 'device',
        },
  ];
}
