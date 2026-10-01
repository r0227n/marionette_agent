import 'package:marionette_agent/marionette_agent.dart';
import 'package:marionette_agent/src/session/session_manager.dart';
import 'package:test/test.dart';

import 'support/interactive_backend.dart';
import 'support/requests.dart';

void main() {
  late InteractiveFake backend;
  late SessionManager manager;
  setUp(() async {
    backend = InteractiveFake();
    manager = SessionManager(() => backend, coreCommands());
    await manager.handle(
      request('connect', params: {'uri': 'http://localhost:1'}),
    );
  });
  tearDown(() => manager.dispose());

  for (final action in ['tap', 'fill', 'focus', 'scrollintoview']) {
    test(
      'find $action rejects a replacement after choosing its matcher',
      () async {
        backend.elements = [
          ElementInfo(key: 'target', type: 'TextField', label: 'Original'),
        ];
        var observations = 0;
        backend.hooks['inspect'] = () async {
          if (++observations == 3) {
            backend.elements = [
              ElementInfo(
                key: 'target',
                type: 'TextField',
                label: 'Replacement',
              ),
            ];
          }
        };
        final result = await manager.handle(
          request(
            'find',
            params: {
              'by': 'label',
              'value': 'Original',
              'exact': true,
              'action': action,
              if (action == 'fill') 'input': 'text',
            },
          ),
        );
        expect(result.error?.code, 'STALE_REF');
        expect(result.error?.outcome, Outcome.notSent);
        expect(backend.calls, isNot(contains(action)));
      },
    );
  }

  test(
    'drag validates both refs in one observation before its only send',
    () async {
      backend.elements = [
        ElementInfo(key: 'from', type: 'Draggable', visible: true),
        ElementInfo(key: 'to', type: 'DragTarget', visible: true),
      ];
      final snapshot = await manager.handle(request('snapshot'));
      final rows = snapshot.data!['elements'] as List;
      backend.calls.clear();
      final result = await manager.handle(
        request(
          'drag',
          params: {
            'from': {'ref': rows[0]['ref']},
            'to': {'ref': rows[1]['ref']},
          },
        ),
      );
      expect(result.exitCode, 0);
      expect(backend.calls.where((call) => call == 'inspect'), hasLength(1));
      expect(backend.calls.where((call) => call == 'drag'), hasLength(1));
      expect(backend.lastArguments, {
        'destination': {'key': 'to'},
      });
      expect(
        (await manager.handle(
          request('get', params: {'action': 'text', 'ref': rows[0]['ref']}),
        )).error?.code,
        'STALE_REF',
      );
    },
  );

  test(
    'drag refuses a changed destination without invalidating the source ref',
    () async {
      final source = ElementInfo(key: 'from', type: 'Draggable', visible: true);
      backend.elements = [
        source,
        ElementInfo(key: 'to', type: 'DragTarget', visible: true),
      ];
      final snapshot = await manager.handle(request('snapshot'));
      final rows = snapshot.data!['elements'] as List;
      backend.elements = [
        source,
        ElementInfo(key: 'to', type: 'Replacement', visible: true),
      ];
      final result = await manager.handle(
        request(
          'drag',
          params: {
            'from': {'ref': rows[0]['ref']},
            'to': {'ref': rows[1]['ref']},
          },
        ),
      );
      expect(result.error?.code, 'STALE_REF');
      expect(backend.calls, isNot(contains('drag')));
      expect(
        (await manager.handle(
          request('get', params: {'action': 'text', 'ref': rows[0]['ref']}),
        )).exitCode,
        0,
      );
    },
  );
}
