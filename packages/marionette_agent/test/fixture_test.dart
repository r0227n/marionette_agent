import 'dart:convert';
import 'dart:io';

import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/backend/marionette_backend.dart';
import 'package:test/test.dart';

import 'backend_test.dart' show ConnectorFixture;

/// Verify handoff fixtures are readable through public API and fixed binding adapter.
void main() {
  test('public response fixtures round trip and retain outcome/exit codes', () {
    final fixtures = asJson(
      jsonDecode(File('test/fixtures/results.json').readAsStringSync()),
    );
    for (final fixture in fixtures.values) {
      final json = asJson(fixture);
      expect(Result.fromJson(json).toJson(), json);
    }
    expect(Result.fromJson(asJson(fixtures['stale'])).exitCode, 4);
    expect(Result.fromJson(asJson(fixtures['unknown'])).exitCode, 5);
  });
  test('fixed binding fixture drives every response primitive', () async {
    final fixtures = asJson(
      jsonDecode(File('test/fixtures/binding_0_6_0.json').readAsStringSync()),
    );
    final connector = ConnectorFixture();
    final backend = MarionetteBackend(connector: connector);
    connector.response = asJson(fixtures['inspect']);
    expect((await backend.inspect()).length, 3);
    connector.response = asJson(fixtures['tap']);
    await backend.tap(
      const ElementTarget(Selector(SelectorKind.key, 'tap_button')),
    );
    connector.response = asJson(fixtures['fill']);
    await backend.fill(const Selector(SelectorKind.key, 'text_input'), '');
    connector.response = asJson(fixtures['swipe']);
    await backend.swipe(
      ElementSwipe(
        const Selector(SelectorKind.key, 'page_view'),
        Direction.left,
      ),
    );
    connector.response = asJson(fixtures['screenshots']);
    expect((await backend.captureScreenshots()).length, 1);
    connector.response = asJson(fixtures['logs']);
    expect((await backend.readLogs()).configured, true);
    connector.response = asJson(fixtures['malformed']);
    await expectLater(backend.inspect(), throwsA(isA<AgentError>()));
  });
}
