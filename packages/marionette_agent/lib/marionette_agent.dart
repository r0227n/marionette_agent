/// Public contract for per-command implementation in Marionette CLI.
///
/// CLI composition uses CliParser; handlers use CommandContext for UI dispatch.
/// See docs/ja/command-contract.ja.md at the repository root for invariants.
library;

export 'src/backend/backend.dart';
export 'src/cli/parser.dart';
export 'src/cli/target_options.dart';
export 'src/commands/command_context.dart';
export 'src/commands/core_commands.dart';
export 'src/commands/registry.dart';
export 'src/protocol/protocol.dart';
export 'src/snapshot/target.dart'
    show TargetQuery, RefQuery, SelectorQuery, ResolvedElement;
