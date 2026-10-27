import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  test('removed Marionette frame recording is rejected before connecting', () {
    expect(
      () => CliParser().parse([
        'record',
        'start',
        'capture.mp4',
        '--platform',
        'flutter',
      ]),
      throwsA(
        isA<AgentError>().having(
          (e) => e.code,
          'code',
          'UNSUPPORTED_CAPABILITY',
        ),
      ),
    );
  });
}
