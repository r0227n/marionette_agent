import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('snapshot fixture exposes duplicate display-only types', (
    tester,
  ) async {
    await tester.pumpWidget(const MarionetteAgentExampleApp());
    final labels = tester
        .widgetList<SnapshotLabel>(find.byType(SnapshotLabel))
        .toList();
    expect(labels, hasLength(2));
    expect(labels.map((label) => label.properties.label), [
      'Filter label A',
      'Filter label B',
    ]);
    expect(labels.map((label) => label.key), everyElement(isNull));
    expect(find.text('Filter label A'), findsOneWidget);
    expect(find.text('Filter label B'), findsOneWidget);
  });

  testWidgets('workflow tabs expose and remove their content', (tester) async {
    await tester.pumpWidget(const MarionetteAgentExampleApp());
    await tester.tap(find.byKey(const ValueKey('about_tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('about_content')), findsOneWidget);
    expect(find.byKey(const ValueKey('text_input')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('controls_tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('text_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_content')), findsNothing);
  });

  testWidgets('returning to Controls resets labels with recreated widgets', (
    tester,
  ) async {
    await tester.pumpWidget(const MarionetteAgentExampleApp());
    await tester.enterText(find.byKey(const ValueKey('text_input')), 'hello');
    await tester.ensureVisible(find.byKey(const ValueKey('page_view')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('page_view')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current page: 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('about_tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('controls_tab')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    expect(find.text('Not edited'), findsOneWidget);
    expect(find.text('5 characters'), findsNothing);
    expect(find.text('Current page: 1'), findsOneWidget);
  });

  testWidgets('exposes the required operation targets', (tester) async {
    await tester.pumpWidget(const MarionetteAgentExampleApp());

    expect(find.byKey(const ValueKey('tap_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('text_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('page_view')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dismissible_item')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('operation_scroll_area')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const ValueKey('dismissible_item')), findsOneWidget);
    expect(find.byKey(const ValueKey('operation_scroll_area')), findsOneWidget);
  });

  testWidgets('tap and fill results are observable', (tester) async {
    await tester.pumpWidget(const MarionetteAgentExampleApp());

    await tester.tap(find.byKey(const ValueKey('tap_button')));
    await tester.enterText(find.byKey(const ValueKey('text_input')), 'hello');
    await tester.pump();

    expect(find.text('Tap count: 1'), findsOneWidget);
    expect(find.text('5 characters'), findsOneWidget);
  });

  testWidgets('page swipe and dismiss are observable', (tester) async {
    await tester.pumpWidget(const MarionetteAgentExampleApp());

    await tester.ensureVisible(find.byKey(const ValueKey('page_view')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('page_view')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current page: 2'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dismissible_item')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('operation_scroll_area')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(
      find.byKey(const ValueKey('dismissible_item')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dismiss_result')), findsOneWidget);
  });
}
