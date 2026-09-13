# Issue #14 再現用の一時研究fixture

これは文書に保存した調査用コードであり、通常のexample entrypoint・製品CLIの変更ではない。実測時はこのDart blockを`example/lib/issue14_research.dart`へ一時展開して、同じexampleの依存/Runnerで実行した。検証後に一時ファイルを削除した。型付き状態取得を実装したものではない。

既存exampleでcontroller省略の入力を調べた後、このfixtureで明示Semantics属性とcontroller付き入力を比較する。操作対象は割当Simulatorだけ。起動・私有URI・runtime・終了手順は[検証記録](issue-14.md)を参照する。

repo rootで次を実行すると、この文書の2つのDart blockから一時ファイルを再生成できる。`MRA_I14_DIR`は検証記録の手順で作った私有directoryを指定する。既存ファイルは上書きしない。

```sh
ruby -e 'blocks = File.read(ARGV[0]).scan(/```dart\n(.*?)```/m).map(&:first); abort "Expected two blocks" unless blocks.length == 2; [ARGV[1], ARGV[2]].zip(blocks).each { |path, code| File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(code) } }' \
  packages/marionette_agent/docs/verification/issue-14-research-fixture.md \
  example/lib/issue14_research.dart "$MRA_I14_DIR/probe.dart"

dart --packages=packages/marionette_agent/.dart_tool/package_config.json \
  "$MRA_I14_DIR/probe.dart" "$MRA_I14_DIR/research-uri" \
  "$MRA_I14_DIR/evidence/research-raw.json" \
  > "$MRA_I14_DIR/probe.log" 2>&1
```

probe呼出しは研究fixture起動後に実行する。baselineのraw取得にはURIファイルを`vm-uri`、保存名を各段階の名前へ変更する。

## Fixture source

```dart
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  MarionetteBinding.ensureInitialized();
  runApp(const MaterialApp(home: ResearchScreen()));
}

class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key});

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  final controller = TextEditingController(text: 'actual input');

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget annotation(String key, String label, {bool? checked, bool? mixed}) {
    return Semantics(
      key: ValueKey(key),
      label: label,
      checked: checked,
      mixed: mixed,
      child: SizedBox(
        height: 64,
        child: ColoredBox(
          color: Colors.lightBlue.shade50,
          child: Center(child: Text('$key: $label')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Issue 14 source/payload fixture')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Semantics(
            key: const ValueKey('semantics_full'),
            label: 'Volume',
            value: '70%',
            hint: 'Adjust volume',
            tooltip: 'Volume help',
            role: SemanticsRole.tabPanel,
            enabled: false,
            child: const SizedBox(
              height: 80,
              child: ColoredBox(
                color: Color(0xffe8f5e9),
                child: Center(child: Text('Volume: 70% (annotation disabled)')),
              ),
            ),
          ),
          const SizedBox(height: 12),
          annotation('duplicate_a', 'Shared label'),
          annotation('duplicate_b', 'Shared label'),
          annotation('checked_true', 'Checked sample', checked: true),
          annotation('checked_false', 'Unchecked sample', checked: false),
          annotation('checked_mixed', 'Mixed sample', mixed: true),
          const SizedBox(height: 24),
          TextField(
            key: const ValueKey('controlled_input'),
            controller: controller,
            enabled: true,
            decoration: const InputDecoration(
              labelText: 'Input label',
              hintText: 'Input placeholder',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const TextField(
            key: ValueKey('disabled_input'),
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Disabled input',
              hintText: 'Disabled placeholder',
              border: OutlineInputBorder(),
            ),
          ),
          Row(
            children: [
              Checkbox(
                key: const ValueKey('mixed_checkbox'),
                tristate: true,
                value: null,
                onChanged: (_) {},
              ),
              const Text('Mixed checkbox'),
              IconButton(
                key: const ValueKey('tooltip_button'),
                tooltip: 'Help tooltip',
                onPressed: () {},
                icon: const Icon(Icons.help_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

## Raw response probe

同じworktreeの`packages/marionette_agent/.dart_tool/package_config.json`を`dart --packages=<absolute-path>`で指定し、次のprobeを私有directoryから実行する。引数は順に私有URIファイルpathとraw JSON保存path。URI自体をコマンド履歴へ書かない。stdoutは要素数だけ。stderrは私有ファイルへ保存し公開しない。CLIによる操作/画像取得と併用し、このprobeだけを動作確認の代用にしない。

```dart
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';
import 'package:marionette_agent/src/backend/marionette_backend.dart';

Future<void> main(List<String> args) async {
  final uri = normalizeUri(File(args[0]).readAsStringSync().trim());
  final service = await vmServiceConnectUri(uri.toString());
  try {
    final vm = await service.getVM();
    final ids = <String>[];
    for (final ref in vm.isolates ?? []) {
      final isolate = await service.getIsolate(ref.id!);
      if (isolate.extensionRPCs?.contains(
            'ext.flutter.marionette.interactiveElements',
          ) ?? false) {
        ids.add(ref.id!);
      }
    }
    if (ids.length != 1) throw StateError('Expected one instrumented isolate');
    final result = await service.callServiceExtension(
      'ext.flutter.marionette.interactiveElements',
      isolateId: ids.single,
    );
    final json = result.json!;
    if (json['status'] != 'Success' || json['elements'] is! List) {
      throw StateError('Invalid inspection response');
    }
    File(args[1]).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(json),
    );
    stdout.writeln('Captured ${(json["elements"] as List).length} elements');
  } finally {
    await service.dispose();
  }
}
```
