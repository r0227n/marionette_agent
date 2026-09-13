import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../protocol/protocol.dart';

enum ScreenshotFormat {
  png('.png'),
  jpeg('.jpg');

  const ScreenshotFormat(this.extension);
  final String extension;

  String destinationPath(String path) {
    final suffix = p.extension(path).toLowerCase();
    if (suffix.isEmpty) return '$path$extension';
    if (suffix != extension && !(this == jpeg && suffix == '.jpeg')) {
      invalid('Screenshot extension must match --screenshot-format');
    }
    return path;
  }
}

/// Single source for common grammar, defaults, recovery and typed values.
class CommonOptions {
  const CommonOptions({
    this.session = 'default',
    this.namespace,
    this.restore,
    this.actionPolicy,
    this.confirmActions,
    this.confirmInteractive = false,
    this.json = false,
    this.debug = false,
    this.timeoutMs = 30000,
    this.contentBoundaries = false,
    this.maxOutput,
    this.idleTimeoutMs,
    this.screenshotFormat = ScreenshotFormat.png,
    this.screenshotQuality = defaultScreenshotQuality,
    this.screenshotDir,
    this.special,
  });
  final String session;
  final String? namespace, restore, actionPolicy, confirmActions;
  final bool confirmInteractive;
  final bool json;
  final bool debug;
  final int timeoutMs;
  final bool contentBoundaries;
  final int? maxOutput;

  /// Null means inherit the running daemon's immutable configuration.
  final int? idleTimeoutMs;
  final ScreenshotFormat screenshotFormat;
  final int screenshotQuality;

  /// Local to this CLI invocation; not persisted or sent to the daemon.
  final String? screenshotDir;
  final String? special;
  static const defaultScreenshotQuality = 90;

  static ArgParser createParser(Map<String, String> environment) => ArgParser()
    ..addOption(
      'session',
      aliases: ['session-name'],
      defaultsTo:
          environment['MARIONETTE_AGENT_SESSION'] ??
          const CommonOptions().session,
      help: 'Session name (CLI > MARIONETTE_AGENT_SESSION > default)',
    )
    ..addOption(
      'restore',
      help: 'Reconnect using a private state file before this command',
    )
    ..addOption('config', help: 'JSON file containing common option defaults')
    ..addOption(
      'action-policy',
      help: 'JSON allow/deny/confirm policy, retained by the session',
    )
    ..addOption(
      'confirm-actions',
      help: 'Comma-separated command names requiring confirmation',
    )
    ..addFlag(
      'confirm-interactive',
      negatable: false,
      help: 'Ask on a terminal when confirmation is required',
    )
    ..addOption('namespace', help: 'Isolate daemon state under a named runtime')
    ..addFlag('json', negatable: false, help: 'One JSON result on stdout')
    ..addFlag(
      'debug',
      negatable: false,
      help: 'Request stages and timing on stderr (default off)',
    )
    ..addOption(
      'timeout',
      defaultsTo:
          environment['MARIONETTE_AGENT_TIMEOUT_MS'] ??
          '${const CommonOptions().timeoutMs}',
      help:
          'Positive deadline in ms, including queue wait '
          '(CLI > MARIONETTE_AGENT_TIMEOUT_MS > 30000)',
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
    ..addOption(
      'screenshot-format',
      defaultsTo: 'png',
      help: 'Screenshot format: png|jpeg (default png; JPEG uses a white background)',
    )
    ..addOption(
      'screenshot-quality',
      help:
          'JPEG only: integer 0-100 (default $defaultScreenshotQuality; 0 maps to quality 1)',
    )
    ..addOption(
      'screenshot-dir',
      valueHelp: 'path',
      help: 'Existing directory for generated screenshot names; explicit screenshot path wins (default temporary)',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help')
    ..addFlag('version', negatable: false, help: 'Show version');

  static CommonOptions parse(ArgResults args) {
    final session = args.option('session')!;
    validateSession(session);
    final namespace = args.option('namespace');
    if (namespace != null) validateSession(namespace);
    if (args.flag('help') && args.flag('version')) {
      invalid('Choose help or version');
    }
    final screenshotFormat = switch (args.option('screenshot-format')) {
      'png' => ScreenshotFormat.png,
      'jpeg' => ScreenshotFormat.jpeg,
      _ => invalid('Expected --screenshot-format png|jpeg'),
    };
    final rawQuality = args.option('screenshot-quality');
    var screenshotQuality = defaultScreenshotQuality;
    if (rawQuality != null) {
      final quality = int.tryParse(rawQuality);
      if (screenshotFormat != ScreenshotFormat.jpeg ||
          !RegExp(r'^[0-9]+$').hasMatch(rawQuality) ||
          quality == null ||
          quality < 0 ||
          quality > 100) {
        invalid(
          '--screenshot-quality requires JPEG and an integer from 0 to 100',
        );
      }
      screenshotQuality = quality;
    }
    final screenshotDir = args.option('screenshot-dir');
    if (screenshotDir != null &&
        (screenshotDir.isEmpty || screenshotDir.contains('\u0000'))) {
      invalid('Expected a non-empty screenshot directory path without NUL');
    }
    return CommonOptions(
      session: session,
      namespace: namespace,
      restore: args.option('restore'),
      actionPolicy: args.option('action-policy'),
      confirmActions: args.option('confirm-actions'),
      confirmInteractive: args.flag('confirm-interactive'),
      json: args.flag('json'),
      screenshotFormat: screenshotFormat,
      screenshotQuality: screenshotQuality,
      debug: args.flag('debug'),
      timeoutMs: parseDurationMs(args.option('timeout')!),
      contentBoundaries: args.flag('content-boundaries'),
      screenshotDir: screenshotDir,
      maxOutput: args.option('max-output') == null
          ? null
          : positiveInteger(args.option('max-output')!),
      idleTimeoutMs: args.option('idle-timeout') == null
          ? null
          : parseDurationMs(
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
    void Function(bool)? debug,
  ) {
    debug?.call(args.flag('debug'));
    final name = args.option('session')!;
    final independent =
        args.flag('help') ||
        args.flag('version') ||
        [
          'doctor',
          'device',
          'install',
          'upgrade',
        ].contains(args.command?.name) ||
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
      : parseDurationMs(args[1], allowZero: true);

  // Recover only output metadata, never an executable invocation. Consume
  // values using the known grammar so a literal --json/--session is not
  // mistaken for an option when another token caused parsing to fail.
  static void recoverOutput(
    ArgParser parser,
    List<String> arguments,
    List<String> commands,
    void Function(String?, bool)? output,
    void Function(bool)? reportDebug,
  ) {
    var grammar = parser;
    String? session = parser.options['session']!.defaultsTo as String?;
    var json = false;
    var debug = false;
    var independent =
        [
          'doctor',
          'device',
          'install',
          'upgrade',
        ].contains(commands.firstOrNull) ||
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
      var name = token.startsWith('--')
          ? token.substring(2, split < 0 ? null : split)
          : token == '-h'
          ? 'help'
          : null;
      if (name == 'session-name') name = 'session';
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
      if (name == 'debug' && split < 0) debug = true;
      if (name == 'help' || name == 'version') independent = true;
    }
    reportDebug?.call(debug);
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
      var name = arg.startsWith('--')
          ? arg.substring(2).split('=').first
          : arg == '-h'
          ? 'help'
          : null;
      if (name == 'session-name') name = 'session';
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
