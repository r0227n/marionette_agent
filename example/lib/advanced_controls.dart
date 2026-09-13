import 'package:flutter/material.dart';

/// Mounted fixtures for typed reads, input, drag, and offscreen scroll targets.
class AdvancedControls extends StatefulWidget {
  const AdvancedControls({super.key});
  @override
  State<AdvancedControls> createState() => _AdvancedControlsState();
}

class _AdvancedControlsState extends State<AdvancedControls> {
  bool checked = false;
  String selected = 'one';
  int doubleTaps = 0, hovers = 0, namedActions = 0;
  String dropped = 'none', keys = 'none';
  final focusNode = FocusNode();
  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('advanced_scroll'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: const ValueKey('role_button'),
            button: true,
            label: 'Named action',
            child: FilledButton(
              onPressed: () => setState(() => namedActions++),
              child: Text(
                'Named actions: $namedActions',
                key: const ValueKey('named_result'),
              ),
            ),
          ),
          const TextField(
            key: ValueKey('advanced_input'),
            decoration: InputDecoration(
              labelText: 'Editable value',
              hintText: 'Type here',
            ),
          ),
          const TextField(
            key: ValueKey('advanced_secret'),
            obscureText: true,
            decoration: InputDecoration(labelText: 'Password'),
          ),
          const TextField(
            key: ValueKey('advanced_disabled'),
            enabled: false,
            decoration: InputDecoration(labelText: 'Disabled input'),
          ),
          Row(
            children: [
              Checkbox(
                key: const ValueKey('advanced_checkbox'),
                value: checked,
                onChanged: (value) => setState(() => checked = value!),
              ),
              Text('Checked: $checked', key: const ValueKey('checked_result')),
            ],
          ),
          DropdownButton<String>(
            key: const ValueKey('advanced_select'),
            value: selected,
            items: const [
              DropdownMenuItem(value: 'one', child: Text('One')),
              DropdownMenuItem(value: 'two', child: Text('Two')),
            ],
            onChanged: (value) => setState(() => selected = value!),
          ),
          Text('Selected: $selected', key: const ValueKey('selected_result')),
          GestureDetector(
            key: const ValueKey('advanced_double'),
            onDoubleTap: () => setState(() => doubleTaps++),
            child: Container(
              height: 48,
              color: Colors.indigo.shade100,
              alignment: Alignment.center,
              child: Text(
                'Double taps: $doubleTaps',
                key: const ValueKey('double_result'),
              ),
            ),
          ),
          Focus(
            key: const ValueKey('advanced_focus'),
            focusNode: focusNode,
            onKeyEvent: (_, event) {
              setState(() => keys = event.logicalKey.keyLabel);
              return KeyEventResult.handled;
            },
            child: Text('Key: $keys', key: const ValueKey('key_result')),
          ),
          MouseRegion(
            key: const ValueKey('advanced_hover'),
            onHover: (_) => setState(() => hovers++),
            child: Text('Hovers: $hovers', key: const ValueKey('hover_result')),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Draggable<String>(
                key: const ValueKey('advanced_drag'),
                data: 'item',
                feedback: const Material(child: Text('Dragging')),
                child: Container(
                  width: 80,
                  height: 56,
                  color: Colors.orange.shade100,
                  alignment: Alignment.center,
                  child: const Text('Drag'),
                ),
              ),
              DragTarget<String>(
                key: const ValueKey('advanced_drop'),
                onAcceptWithDetails: (details) =>
                    setState(() => dropped = details.data),
                builder: (_, _, _) => Container(
                  width: 100,
                  height: 56,
                  color: Colors.green.shade100,
                  alignment: Alignment.center,
                  child: Text(
                    'Drop: $dropped',
                    key: const ValueKey('drop_result'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 700),
          const Text(
            'Advanced bottom reached',
            key: ValueKey('advanced_bottom'),
          ),
        ],
      ),
    ),
  );
}
