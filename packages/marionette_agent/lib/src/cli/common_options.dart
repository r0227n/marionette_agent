import 'package:args/args.dart';

import '../protocol/protocol.dart';

/// Single source for common grammar, defaults, recovery and typed values.
class CommonOptions {
  const CommonOptions({
    this.session = 'default',
    this.json = false,
    this.timeoutMs = 30000,
    this.contentBoundaries = false,
    this.maxOutput,
    this.idleTimeoutMs,
    this.special,
  });
  final String session;
  final bool json;
  final int timeoutMs;
  final bool contentBoundaries;
  final int? maxOutput;

  /// Null means inherit the running daemon's immutable configuration.
  final int? idleTimeoutMs;
  final String? special;
  static const defaultIdleTimeoutMs = 3600000;

  static ArgParser createParser() => ArgParser()
    ..addOption('session', defaultsTo: 'default', help: 'Session name')
    ..addFlag('json', negatable: false, help: 'One JSON result on stdout')
    ..addOption(
      'timeout',
      defaultsTo: '30000',
      help: 'Positive deadline in milliseconds',
    )
    ..addFlag(
      'content-boundaries',
      negatable: false,
      help: 'Snapshot/log items: nonce markers in text, metadata in JSON (default off)',
    )
    ..addOption(
      'max-output',
      help: 'Positive Unicode code point budget for whole snapshot/log items (default unlimited)',
    )
    ..addOption(
      'idle-timeout',
      help: 'Daemon idle duration: ms, 10s, 3m, 1h (default 1h; 0 disables)',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help')
    ..addFlag('version', negatable: false, help: 'Show version');

  static bool validSession(String name) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(name);

  static void validateSession(String name) {
    if (!validSession(name)) invalid('Invalid session name');
  }

  static int? outputLimit(Object? value) {
    if (value == null) return null;
    if (value is! int || value <= 0) invalid('Expected a positive integer');
    return value;
  }

  static int positiveInteger(String value) {
    final result = int.tryParse(value);
    if (!RegExp(r'^[0-9]+$').hasMatch(value) || result == null) {
      invalid('Expected a positive integer');
    }
    return outputLimit(result)!;
  }

  static int duration(
    String value, {
    bool allowZero = false,
    bool units = false,
  }) {
    final match = RegExp(units ? r'^([0-9]+)(ms|s|m|h)?$' : r'^([0-9]+)$')
        .firstMatch(value);
    if (match == null) invalid('Invalid duration');
    final count = BigInt.parse(match.group(1)!);
    final unit = units ? match.group(2) : null;
    final multiplier = switch (unit) {
      's' => 1000,
      'm' => 60000,
      'h' => 3600000,
      _ => 1,
    };
    final ms = count * BigInt.from(multiplier);
    // Duration uses microseconds; DateTime must also represent the deadline.
    if (ms > BigInt.from(9223372036854775) ||
        (!allowZero && ms == BigInt.zero)) {
      invalid('Duration is out of range');
    }
    final result = ms.toInt();
    try {
      DateTime.now().add(Duration(milliseconds: result));
    } on ArgumentError {
      invalid('Duration is out of range');
    }
    return result;
  }

  static CommonOptions parse(ArgResults args) {
    final session = args.option('session')!;
    validateSession(session);
    if (args.flag('help') && args.flag('version')) {
      invalid('Choose help or version');
    }
    return CommonOptions(
      session: session,
      json: args.flag('json'),
      timeoutMs: duration(args.option('timeout')!),
      contentBoundaries: args.flag('content-boundaries'),
      maxOutput: args.option('max-output') == null
          ? null
          : positiveInteger(args.option('max-output')!),
      idleTimeoutMs: args.option('idle-timeout') == null
          ? null
          : duration(
              args.option('idle-timeout')!,
              allowZero: true,
              units: true,
            ),
      special: args.flag('help')
          ? 'help'
          : args.flag('version')
          ? 'version'
          : null,
    );
  }

  /// Recover output mode before validation can reject a common value.
  static void reportOutput(
    ArgResults args,
    void Function(String?, bool)? output,
  ) {
    final name = args.option('session')!;
    final independent =
        args.flag('help') ||
        args.flag('version') ||
        (args.command?.name == 'workflow' &&
            args.command?.command?.name != 'run') ||
        (args.command?.name == 'session' &&
            args.command?.command?.name == 'list');
    output?.call(
      independent || !validSession(name) ? null : name,
      args.flag('json'),
    );
  }

  static int daemonIdle(List<String> args) => args.length == 1
      ? defaultIdleTimeoutMs
      : duration(args[1], allowZero: true);

  // Recover only output metadata, never an executable invocation. Consume
  // values using the known grammar so a literal --json/--session is not
  // mistaken for an option when another token caused parsing to fail.
  static void recoverOutput(
    ArgParser parser,
    List<String> arguments,
    List<String> commands,
    void Function(String?, bool)? output,
  ) {
    var grammar = parser;
    String? session = 'default';
    var json = false;
    var independent =
        (commands.firstOrNull == 'workflow' && !commands.contains('run')) ||
        (commands.firstOrNull == 'session' && commands.contains('list'));
    for (var i = 0; i < arguments.length; i++) {
      final token = arguments[i];
      if (token == '--') break;
      if (grammar.commands[token] case final ArgParser child) {
        grammar = child;
        continue;
      }
      final split = token.indexOf('=');
      final name = token.startsWith('--')
          ? token.substring(2, split < 0 ? null : split)
          : token == '-h'
          ? 'help'
          : null;
      final option = grammar.options[name] ?? parser.options[name];
      if (option == null) continue;
      String? value;
      if (!option.isFlag) {
        value = split >= 0
            ? token.substring(split + 1)
            : i + 1 < arguments.length
            ? arguments[++i]
            : null;
      }
      if (!identical(option, parser.options[name])) continue;
      if (name == 'session') session = value;
      if (name == 'json' && split < 0) json = true;
      if (name == 'help' || name == 'version') independent = true;
    }
    output?.call(
      independent || session == null || !validSession(session) ? null : session,
      json,
    );
  }

  static void rejectDuplicateOptions(ArgParser parser, List<String> arguments) {
    var grammar = parser;
    final seen = <String>{};
    for (var i = 0; i < arguments.length; i++) {
      final arg = arguments[i];
      if (arg == '--') break;
      if (grammar.commands[arg] case final ArgParser child) {
        grammar = child;
        continue;
      }
      final name = arg.startsWith('--')
          ? arg.substring(2).split('=').first
          : arg == '-h'
          ? 'help'
          : null;
      final option = grammar.options[name] ?? parser.options[name];
      if (option == null) {
        if (RegExp(r'^-h+$').hasMatch(arg)) {
          for (var j = 1; j < arg.length; j++) {
            if (!seen.add('help')) invalid('Duplicate option');
          }
        }
        continue;
      }
      if (!seen.add(option.name)) invalid('Duplicate option');
      if (option.isFlag && arg.contains('=')) {
        invalid('Flag does not accept a value');
      }
      if (!option.isFlag && !arg.contains('=')) i++;
    }
  }
}
