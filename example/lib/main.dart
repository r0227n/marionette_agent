import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'mapped_screenshot.dart';

final PrintLogCollector operationLogCollector = PrintLogCollector();

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: operationLogCollector),
    );
    if (!const bool.fromEnvironment('DISABLE_MAPPED_SCREENSHOT')) {
      registerMappedScreenshot();
    }
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  operationLogCollector.addLog('example started');
  runApp(const MarionetteAgentExampleApp());
}

class MarionetteAgentExampleApp extends StatelessWidget {
  const MarionetteAgentExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marionette Agent Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MarionetteAgentExampleScreen(),
    );
  }
}

class MarionetteAgentExampleScreen extends StatefulWidget {
  const MarionetteAgentExampleScreen({super.key});

  @override
  State<MarionetteAgentExampleScreen> createState() =>
      _MarionetteAgentExampleScreenState();
}

class _MarionetteAgentExampleScreenState
    extends State<MarionetteAgentExampleScreen> {
  int _tab = 0;
  int _tapCount = 0;
  int _pageIndex = 0;
  bool _dismissibleVisible = true;
  String _inputStatus = 'Not edited';

  void _record(String message) {
    operationLogCollector.addLog(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marionette Agent Example')),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              key: const ValueKey('controls_tab'),
              onPressed: () => setState(() => _tab = 0),
              child: const Text('Controls'),
            ),
            TextButton(
              key: const ValueKey('about_tab'),
              onPressed: () => setState(() {
                _tab = 1;
                // Controls are recreated on return, including their local state.
                _inputStatus = 'Not edited';
                _pageIndex = 0;
              }),
              child: const Text('About'),
            ),
          ],
        ),
      ),
      body: _tab == 1
          ? const Center(
              child: Text('Workflow fixture', key: ValueKey('about_content')),
            )
          : ListView(
              key: const ValueKey('operation_scroll_area'),
              padding: const EdgeInsets.all(16),
              children: [
                _Section(
                  title: 'Tap',
                  child: Row(
                    children: [
                      FilledButton(
                        key: const ValueKey('tap_button'),
                        onPressed: () {
                          setState(() => _tapCount++);
                          _record('tap button pressed: $_tapCount');
                        },
                        child: const Text('Tap me'),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Tap count: $_tapCount',
                        key: const ValueKey('tap_result'),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: 'Fill',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('text_input'),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Test input',
                        ),
                        onChanged: (value) {
                          setState(
                            () => _inputStatus = '${value.length} characters',
                          );
                          _record('text input changed');
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(_inputStatus, key: const ValueKey('fill_result')),
                    ],
                  ),
                ),
                _Section(
                  title: 'PageView swipe',
                  child: Column(
                    children: [
                      SizedBox(
                        height: 140,
                        child: PageView(
                          key: const ValueKey('page_view'),
                          onPageChanged: (index) {
                            setState(() => _pageIndex = index);
                            _record('page changed: ${index + 1}');
                          },
                          children: const [
                            _SwipePage(label: 'Page 1', color: Colors.indigo),
                            _SwipePage(label: 'Page 2', color: Colors.teal),
                            _SwipePage(label: 'Page 3', color: Colors.orange),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Current page: ${_pageIndex + 1}',
                        key: const ValueKey('page_result'),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: 'Dismissible swipe',
                  child: _dismissibleVisible
                      ? Dismissible(
                          key: const ValueKey('dismissible_item'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) {
                            setState(() => _dismissibleVisible = false);
                            _record('dismissible item dismissed');
                          },
                          child: const ListTile(
                            title: Text('Swipe left to dismiss'),
                            trailing: Icon(Icons.swipe_left),
                          ),
                        )
                      : const Text(
                          'Item dismissed',
                          key: ValueKey('dismiss_result'),
                        ),
                ),
                for (var index = 1; index <= 6; index++)
                  ListTile(
                    key: ValueKey('scroll_item_$index'),
                    leading: const Icon(Icons.keyboard_arrow_down),
                    title: Text('Scroll item $index'),
                  ),
                FilledButton.tonal(
                  key: const ValueKey('log_button'),
                  onPressed: () => _record('manual log entry added'),
                  child: const Text('Add log entry'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Bottom reached',
                    key: ValueKey('scroll_result'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SwipePage extends StatelessWidget {
  const _SwipePage({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withValues(alpha: 0.15),
      child: Center(
        child: Text(label, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
