import '../backend/backend.dart';
import '../protocol/protocol.dart';
import '../snapshot/snapshot_service.dart' show SelectorQuery, TargetQuery;
import 'arguments.dart';
import 'command_context.dart';

Future<Json> handleGet(CommandContext context, Json params) async {
  final request = GetRequest.parse(params);
  switch (request.action) {
    case 'value':
      final resolved = await context.resolveRead(request.target!);
      return {
        'property': 'value',
        'known': resolved.element.inputValue != null,
        'value': resolved.element.inputValue,
      };
    case 'text':
      final resolved = await context.resolveRead(request.target!);
      return {'text': resolved.element.text};
    case 'box':
      final resolved = await context.resolveRead(request.target!);
      return {
        'bounds': resolved.element.bounds,
        'unit': 'flutter_logical_pixels',
      };
    case 'count':
      final matches = await context.count(request.selector!);
      context.check();
      return {'count': matches.length, 'selector': request.selector!.toJson()};
  }
  throw StateError('unreachable get action ${request.action}');
}

class GetRequest {
  const GetRequest._({required this.action, this.target, this.selector});

  final String action;
  final TargetQuery? target;
  final Selector? selector;

  static GetRequest parse(Json params) {
    final action = params['action'];
    if (!['text', 'value', 'box', 'count'].contains(action)) {
      invalid('Usage: get text|box <ref|selector> | get count <selector>');
    }
    final allowed = {
      'action',
      'ref',
      ...SelectorKind.values.map((k) => k.name),
    };
    if (params.keys.any((key) => !allowed.contains(key))) {
      invalid('Unknown get parameter');
    }
    final target = {
      if (params.containsKey('ref')) 'ref': params['ref'],
      for (final kind in SelectorKind.values)
        if (params.containsKey(kind.name)) kind.name: params[kind.name],
    };
    if (action == 'count') {
      if (target.containsKey('ref')) invalid('get count requires a selector');
      return GetRequest._(
        action: action as String,
        selector: (decodeTarget(target) as SelectorQuery).selector,
      );
    }
    return GetRequest._(action: action as String, target: decodeTarget(target));
  }
}
