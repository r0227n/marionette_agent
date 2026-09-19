import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_agent_flutter/marionette_agent_flutter.dart';

Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

void main() {
  testWidgets('hidden view renders only while explicitly opted in', (
    tester,
  ) async {
    await lifecycle(tester, AppLifecycleState.resumed);
    final value = ValueNotifier(0);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: value,
        builder: (_, count, _) =>
            Text('$count', textDirection: TextDirection.ltr),
      ),
    );
    await lifecycle(tester, AppLifecycleState.hidden);
    final dispose = enableHeadlessRendering();
    try {
      expect(tester.binding.lifecycleState, AppLifecycleState.hidden);
      expect(tester.binding.framesEnabled, isFalse);
      value.value = 1;
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('1'), findsOneWidget);
      await lifecycle(tester, AppLifecycleState.paused);
      value.value = 2;
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('2'), findsOneWidget);
    } finally {
      dispose();
    }
    await tester.pump();
    value.value = 3;
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.text('2'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });

  for (final listenerFirst in [false, true]) {
    testWidgets(
      'native lifecycle stays valid (listener first: $listenerFirst)',
      (tester) async {
        await lifecycle(tester, AppLifecycleState.resumed);
        final states = <AppLifecycleState>[];
        late AppLifecycleListener listener;
        if (listenerFirst) {
          listener = AppLifecycleListener(onStateChange: states.add);
        }
        final dispose = enableHeadlessRendering();
        if (!listenerFirst) {
          listener = AppLifecycleListener(onStateChange: states.add);
        }
        try {
          await lifecycle(tester, AppLifecycleState.hidden);
          await lifecycle(tester, AppLifecycleState.resumed);
          await lifecycle(tester, AppLifecycleState.paused);
          await lifecycle(tester, AppLifecycleState.resumed);
          expect(states, [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]);
          expect(tester.takeException(), isNull);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 32));
          expect(tester.binding.hasScheduledFrame, isFalse);
        } finally {
          dispose();
          listener.dispose();
        }
      },
    );
  }
}
