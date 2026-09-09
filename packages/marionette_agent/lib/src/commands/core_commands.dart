import '../protocol/protocol.dart';
import 'registry.dart';

/// Registers A01-A06 commands. Register additional features explicitly in the same registry.
CommandRegistry coreCommands() =>
    CommandRegistry()..register('snapshot', (context, params) {
      if (params.isNotEmpty) invalid('Usage: snapshot');
      return context.snapshot();
    });
