import '../protocol/protocol.dart';

const batchCommands = {
  'snapshot',
  'get',
  'is',
  'find',
  'tap',
  'click',
  'fill',
  'type',
  'focus',
  'hover',
  'check',
  'uncheck',
  'select',
  'dblclick',
  'press',
  'keydown',
  'keyup',
  'keyboard',
  'clipboard',
  'scroll',
  'swipe',
  'scrollintoview',
  'drag',
  'wait',
  'logs',
};

List<Json> validateBatch(Json params) {
  final steps = params['steps'];
  if (params.length != 1 ||
      steps is! List ||
      steps.isEmpty ||
      steps.length > 100) {
    invalid('Batch requires 1 to 100 commands');
  }
  return steps.map((raw) {
    if (raw is! Map ||
        raw.length != 2 ||
        !batchCommands.contains(raw['command']) ||
        raw['params'] is! Map) {
      invalid('Unsupported batch command');
    }
    return {'command': raw['command'], 'params': asJson(raw['params'])};
  }).toList();
}
