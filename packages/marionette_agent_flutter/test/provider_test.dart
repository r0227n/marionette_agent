import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_agent_flutter/marionette_agent_flutter.dart';

void main() {
  testWidgets(
    'typed values distinguish empty, password, disabled and mixed state',
    (tester) async {
      final controller = TextEditingController(text: 'secret');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const TextField(
                  key: ValueKey('empty'),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'Type here',
                  ),
                ),
                TextField(
                  key: const ValueKey('secret'),
                  controller: controller,
                  obscureText: true,
                ),
                const TextField(key: ValueKey('disabled'), enabled: false),
                const Checkbox(
                  key: ValueKey('mixed'),
                  tristate: true,
                  value: null,
                  onChanged: null,
                ),
                Semantics(
                  key: const ValueKey('role'),
                  button: true,
                  label: 'Named action',
                  child: const Text('Label'),
                ),
              ],
            ),
          ),
        ),
      );
      final entries = AgentExtensionProvider().inspect()['elements'] as List;
      Map row(String key) =>
          entries.cast<Map>().singleWhere((entry) => entry['key'] == key);
      expect(row('empty')['inputValue'], '');
      expect(row('empty')['label'], 'Email');
      expect(row('empty')['placeholder'], 'Type here');
      expect(row('secret').containsKey('inputValue'), false);
      expect(row('secret').containsKey('text'), false);
      expect(row('disabled')['enabled'], false);
      expect(row('mixed').containsKey('checked'), false);
      expect(row('role')['role'], 'button');
    },
  );

  testWidgets(
    'type inserts at selection, uses input formatters, and refuses disabled fields',
    (tester) async {
      final controller = TextEditingController(text: 'abcd')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 3);
      addTearDown(controller.dispose);
      var last = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(
                  key: const ValueKey('edit'),
                  controller: controller,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp('[0-9]')),
                  ],
                  onChanged: (value) => last = value,
                ),
                const TextField(key: ValueKey('disabled'), enabled: false),
              ],
            ),
          ),
        ),
      );
      final provider = AgentExtensionProvider();
      await provider.interact({
        'action': 'type',
        'target': {'key': 'edit'},
        'arguments': {'input': 'X9'},
      });
      await tester.pump();
      expect(controller.text, 'aXd');
      expect(last, 'aXd');
      expect(controller.selection.baseOffset, 2);
      await expectLater(
        provider.interact({
          'action': 'type',
          'target': {'key': 'disabled'},
          'arguments': {'input': 'secret'},
        }),
        throwsA(isA<AgentExtensionFailure>()),
      );
    },
  );

  testWidgets(
    'check and select are idempotent and reject unmatched or ambiguous targets',
    (tester) async {
      var checked = false, changes = 0;
      var selected = 'one';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  Checkbox(
                    key: const ValueKey('check'),
                    value: checked,
                    onChanged: (value) => setState(() {
                      checked = value!;
                      changes++;
                    }),
                  ),
                  DropdownButton<String>(
                    key: const ValueKey('select'),
                    value: selected,
                    items: const [
                      DropdownMenuItem(value: 'one', child: Text('One')),
                      DropdownMenuItem(value: 'two', child: Text('Two')),
                    ],
                    onChanged: (value) => setState(() => selected = value!),
                  ),
                  const Text('duplicate'),
                  const Text('duplicate'),
                ],
              ),
            ),
          ),
        ),
      );
      final provider = AgentExtensionProvider();
      Future<void> check() => provider.interact({
        'action': 'check',
        'target': {'key': 'check'},
        'arguments': {},
      });
      await check();
      await tester.pump();
      await check();
      await tester.pump();
      expect(checked, true);
      expect(changes, 1);
      await provider.interact({
        'action': 'select',
        'target': {'key': 'select'},
        'arguments': {'input': 'two'},
      });
      await tester.pump();
      expect(selected, 'two');
      await expectLater(
        provider.interact({
          'action': 'select',
          'target': {'key': 'select'},
          'arguments': {'input': 'missing'},
        }),
        throwsA(isA<AgentExtensionFailure>()),
      );
      await expectLater(
        provider.interact({
          'action': 'focus',
          'target': {'text': 'duplicate'},
          'arguments': {},
        }),
        throwsA(
          isA<AgentExtensionFailure>().having(
            (error) => error.code,
            'code',
            'AMBIGUOUS_TARGET',
          ),
        ),
      );
    },
  );

  testWidgets(
    'scroll-to reveals mounted offscreen target without repeated finder gestures',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 1200),
                  Text('Bottom', key: ValueKey('bottom')),
                ],
              ),
            ),
          ),
        ),
      );
      final provider = AgentExtensionProvider();
      Map target() => (provider.inspect()['elements'] as List)
          .cast<Map>()
          .singleWhere((entry) => entry['key'] == 'bottom');
      expect(target()['visible'], false);
      final moving = provider.interact({
        'action': 'scrollintoview',
        'target': {'key': 'bottom'},
        'arguments': {},
      });
      await tester.pumpAndSettle();
      await moving;
      expect(target()['visible'], true);
    },
  );

  testWidgets('keydown/up route through Focus and reject unbalanced events', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: node,
          onKeyEvent: (_, event) {
            count++;
            return KeyEventResult.handled;
          },
          child: const Text('Keys'),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    final provider = AgentExtensionProvider();
    await provider.interact({
      'action': 'keydown',
      'arguments': {'key': 'a', 'modifiers': []},
    });
    await expectLater(
      provider.interact({
        'action': 'keydown',
        'arguments': {'key': 'a', 'modifiers': []},
      }),
      throwsA(isA<AgentExtensionFailure>()),
    );
    await provider.interact({
      'action': 'keyup',
      'arguments': {'key': 'a', 'modifiers': []},
    });
    expect(count, greaterThanOrEqualTo(2));
    await expectLater(
      provider.interact({
        'action': 'keyup',
        'arguments': {'key': 'a', 'modifiers': []},
      }),
      throwsA(isA<AgentExtensionFailure>()),
    );
  });
}
