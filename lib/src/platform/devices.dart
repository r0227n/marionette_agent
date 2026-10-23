import 'package:marionette_agent_ios/marionette_agent_ios.dart';
import 'package:marionette_agent_android/marionette_agent_android.dart';
import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

Future<List<Map<String, Object?>>> listDevices(
  String platform,
  DateTime deadline,
) => switch (platform) {
  'ios' => listIosDevices(deadline),
  'android' => listAndroidDevices(deadline),
  _ => throw const PlatformException(
    'INVALID_ARGUMENT',
    'Expected ios or android',
  ),
};
