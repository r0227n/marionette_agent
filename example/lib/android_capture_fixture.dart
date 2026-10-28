import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android-only debug fixture for native capture; all content is synthetic.
class AndroidCaptureFixture extends StatefulWidget {
  const AndroidCaptureFixture({super.key});
  @override
  State<AndroidCaptureFixture> createState() => _AndroidCaptureFixtureState();
}

class _AndroidCaptureFixtureState extends State<AndroidCaptureFixture> {
  static const channel = MethodChannel('marionette.example/nativeCapture');
  String status = 'Dummy data only';
  Future<void> run(String action) async {
    try {
      await channel.invokeMethod<void>(action);
      if (mounted) setState(() => status = action);
    } on PlatformException {
      if (mounted) {
        setState(() => status = 'Unavailable on this Android version');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Workflow fixture', key: ValueKey('about_content')),
      const Text('Native capture fixture', style: TextStyle(fontSize: 22)),
      const Text('Android system UI and protected-window verification'),
      for (final item in const {
        'permission': 'Request camera permission',
        'seedPhoto': 'Create dummy picker image',
        'photoPicker': 'Open Photo Picker (API 33+)',
        'documentPicker': 'Open file picker',
        'secureOn': 'Enable FLAG_SECURE',
        'secureOff': 'Disable fixture FLAG_SECURE',
      }.entries)
        FilledButton(
          key: ValueKey('native_${item.key}'),
          onPressed: () => run(item.key),
          child: Text(item.value),
        ),
      const TextField(
        key: ValueKey('native_text_input'),
        decoration: InputDecoration(labelText: 'Dummy keyboard input'),
      ),
      Text(status, key: const ValueKey('native_status')),
    ],
  );
}
