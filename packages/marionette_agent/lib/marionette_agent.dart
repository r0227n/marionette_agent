/// Public contract for per-command implementation in Marionette CLI.
///
/// Use args parsing plus CommandContext for target validation and UI dispatch.
/// See docs/command-contract.md for examples and invariants.
library;

export 'src/backend/backend.dart';
export 'src/backend/fake_backend.dart';
export 'src/cli/parser.dart';
export 'src/cli/target_options.dart';
export 'src/commands/command_context.dart';
export 'src/commands/core_commands.dart';
export 'src/commands/registry.dart';
export 'src/protocol/protocol.dart';
export 'src/snapshot/snapshot_service.dart'
    show TargetQuery, RefQuery, SelectorQuery;
