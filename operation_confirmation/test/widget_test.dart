import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:operation_confirmation/main.dart';

void main() {
  testWidgets('exposes the required operation targets', (tester) async {
    await tester.pumpWidget(const OperationConfirmationApp());

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
    await tester.pumpWidget(const OperationConfirmationApp());

    await tester.tap(find.byKey(const ValueKey('tap_button')));
    await tester.enterText(find.byKey(const ValueKey('text_input')), 'hello');
    await tester.pump();

    expect(find.text('Tap count: 1'), findsOneWidget);
    expect(find.text('5 characters'), findsOneWidget);
  });

  testWidgets('page swipe and dismiss are observable', (tester) async {
    await tester.pumpWidget(const OperationConfirmationApp());

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
