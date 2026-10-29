// Copied into a standalone app by tool/verify_binding_compatibility.py.
// No agent provider: exercise each published binding's actual wire protocol.
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  MarionetteBinding.ensureInitialized(const MarionetteConfiguration());
  runApp(const MaterialApp(home: CompatibilityScreen()));
}

class CompatibilityScreen extends StatefulWidget {
  const CompatibilityScreen({super.key});

  @override
  State<CompatibilityScreen> createState() => _CompatibilityScreenState();
}

class _CompatibilityScreenState extends State<CompatibilityScreen> {
  final controller = TextEditingController();
  int count = 0;
  int page = 0;

  @override
  void initState() {
    super.initState();
    // Pre-0.4 bindings update controllers without calling onChanged.
    controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Binding compatibility')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(String.fromEnvironment('BINDING_VERSION')),
          Semantics(
            identifier: 'compat.tap',
            child: ElevatedButton(
              key: const ValueKey('tap_button'),
              onPressed: () => setState(() => count++),
              child: const Text('Tap once'),
            ),
          ),
          Text('Tap count: $count', key: const ValueKey('tap_result')),
          TextField(key: const ValueKey('text_input'), controller: controller),
          Text(
            'Input length: ${controller.text.length}',
            key: const ValueKey('fill_result'),
          ),
          SizedBox(
            height: 160,
            child: PageView(
              key: const ValueKey('page_view'),
              onPageChanged: (value) => setState(() => page = value),
              children: const [
                Center(child: Text('First page')),
                Center(child: Text('Second page')),
              ],
            ),
          ),
          Text('Page: $page', key: const ValueKey('page_result')),
        ],
      ),
    ),
  );
}
