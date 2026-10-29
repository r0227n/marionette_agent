import 'dart:async';

import 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';

NativeElement nativeButton({
  String text = 'Allow',
  double x = 10,
  bool enabled = true,
  String identifier = 'allow',
}) => NativeElement(
  type: 'Button',
  text: text,
  identifier: identifier,
  enabled: enabled,
  bounds: NativeBounds(x, 20, 100, 40),
);

class FakeNativeBackend implements NativeUiBackend {
  List<NativeElement> elements = [nativeButton()];
  final calls = <String>[];
  final taps = <(double, double)>[];
  final swipes = <(double, double, double, double)>[];
  Completer<void>? inspecting, tapping;
  Object? failure;
  @override
  Future<List<NativeElement>> inspect(String device, DateTime deadline) async {
    calls.add('inspect:$device');
    if (inspecting != null) await inspecting!.future;
    return elements;
  }

  @override
  Future<void> tap(String device, double x, double y, DateTime deadline) async {
    calls.add('tap:$device');
    taps.add((x, y));
    if (tapping != null) await tapping!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> swipe(
    String device,
    double startX,
    double startY,
    double endX,
    double endY,
    DateTime deadline,
  ) async {
    calls.add('swipe:$device');
    swipes.add((startX, startY, endX, endY));
  }
}
