import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Explicit debug controls for observing real iOS UI in capture verification.
class NativeCaptureFixture extends StatelessWidget {
  const NativeCaptureFixture({super.key});
  static const _channel = MethodChannel('marionette.example/native-capture');

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Workflow fixture', key: ValueKey('about_content')),
        if (kDebugMode &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.iOS) ...[
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('native_photo_permission'),
            onPressed: () => _channel.invokeMethod<void>('photoPermission'),
            child: const Text('Photo permission'),
          ),
          FilledButton(
            key: const ValueKey('native_photo_picker'),
            onPressed: () => _channel.invokeMethod<void>('photoPicker'),
            child: const Text('Photo picker'),
          ),
          const Text('Use dummy photos on a dedicated Simulator.'),
        ],
      ],
    ),
  );
}
