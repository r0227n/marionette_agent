import 'package:test/test.dart';

import '../integration_test/support/evidence.dart';

void main() {
  test('schema inspection does not acquire screenshot device arguments', () {
    final args = ['workflow', 'schema', 'screenshot'];
    expect(nativeScreenshotArguments(args), args);
  });

  test('explicit screenshot target is preserved', () {
    final args = ['screenshot', '--device', 'selected-device', 'screen.png'];
    expect(nativeScreenshotArguments(args), args);
  });
}
