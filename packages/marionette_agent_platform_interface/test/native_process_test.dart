import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent_platform_interface/host_support.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('native-process-');
  });
  tearDown(() => dir.delete(recursive: true));
  Future<String> script(String source) async {
    final file = File('${dir.path}/tool.dart');
    await file.writeAsString(source);
    return file.path;
  }

  test('captures binary stdout and never forwards secret stderr', () async {
    final path = await script(
      "import 'dart:io'; void main() { stdout.add([0, 255, 13, 10]); stderr.write('screen-secret'); }",
    );
    final bytes = await runNativeProcess(Platform.resolvedExecutable, [
      path,
    ], DateTime.now().add(const Duration(seconds: 5)));
    expect(bytes, [0, 255, 13, 10]);
  });
  test('nonzero failure is normalized without screen text', () async {
    final path = await script(
      "import 'dart:io'; void main() { stderr.write('screen-secret'); exit(3); }",
    );
    await expectLater(
      runNativeProcess(Platform.resolvedExecutable, [
        path,
      ], DateTime.now().add(const Duration(seconds: 5))),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'IO_ERROR')
            .having((e) => '$e', 'redacted', isNot(contains('screen-secret'))),
      ),
    );
  });
  test('deadline kills owned process before delayed side effect', () async {
    final marker = File('${dir.path}/late');
    final path = await script(
      "import 'dart:io'; Future<void> main() async { await Future<void>.delayed(const Duration(seconds: 2)); File(${jsonEncode(marker.path)}).writeAsStringSync('late'); }",
    );
    await expectLater(
      runNativeProcess(Platform.resolvedExecutable, [
        path,
      ], DateTime.now().add(const Duration(milliseconds: 300))),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'TIMEOUT'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(marker.existsSync(), isFalse);
  });
  test(
    'missing native tool reports actionable unsupported capability',
    () async {
      await expectLater(
        runNativeProcess(
          '${dir.path}/missing',
          [],
          DateTime.now().add(const Duration(seconds: 1)),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_CAPABILITY',
          ),
        ),
      );
    },
  );
}
