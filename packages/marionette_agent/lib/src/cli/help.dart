import 'package:args/args.dart';

String cliUsage(ArgParser parser, Iterable<String> commands) =>
    'Usage: marionette-agent [options] <command>\n${parser.usage}\n\n'
    'Commands: ${commands.join(', ')}\n'
    'mcp [--tools core,inspect,actions,workflow,record|all] (MCP stdio server; default core)\n'
    'skills [list] | skills get <name> [name...] [--full] | skills get --all [--full]\n'
    'skills path [name] | skills --help (bundled guides; no download or connection)\n'
    'Start with marionette-agent skills get core; use --full for references and templates.\n'
    'doctor [--probe-uri <uri>] (read-only; no connection required)\n'
    'snapshot [--key <value> | --identifier <value> | --text <value> | --type <value>]\n'
    'Snapshot filters observed values; zero/multiple matches are valid. Full observation determines ref safety.\n'
    'get text|box <ref|selector> | get count <selector>\n'
    'get preserves refs; box uses Flutter logical pixels; missing values are null.\n'
    'connect <uri> | session list | session show | close [--all] | snapshot\n'
    'close --all stops all sessions; cannot combine with --session. Stops apps owned by launch.\n'
    'swipe <ref|selector> <left|right|up|down> [--distance <n>]\n'
    'swipe --start-x <n> --start-y <n> --end-x <n> --end-y <n>\n'
    'Directions describe finger movement; verify the result with snapshot.\n'
    'tap <ref|selector> | tap --x <n> --y <n> | fill <ref|selector> <text>\n'
    'scroll <ref|selector> <left|right|up|down> [--distance <n>]\n'
    'scroll uses finger movement direction; reaching content is not guaranteed.\n'
    'screenshot [--annotate] [path] | logs\n'
    '  --annotate requires a valid snapshot and an opt-in mapped screenshot provider.\n'
    'Screenshot destination: explicit path > --screenshot-dir > temporary directory.\n'
    'Screenshot directories must exist; --screenshot-dir must not be a symlink.\n'
    'is visible <ref|selector> (true, false, or unknown; preserves refs)\n'
    'Screenshot extensions: .png or .jpg/.jpeg; missing extension is appended.\n'
    'Multiple images: name-1.ext, name-2.ext; existing files are refused.\n'
    'Path and directory omitted: private screen.png/screen.jpg; conversion uses --timeout.\n'
    'wait <selector> [--state exists|gone] [--poll-interval <ms>]\n'
    'wait observes only; run snapshot before the next UI operation.\n'
    'launch <project> --platform tester|ios|android|macos|web (headless; close stops owned app)\n'
    'record start <path> --platform ios|android|macos|web --device <id>\n'
    'web: --device display:<index>@ws://127.0.0.1:<port>/devtools/page/<id> (.mov; whole display, visible Chrome on macOS)\n'
    'record start <path.mp4> --platform flutter [--fps 10] (connected app frames; headless compatible)\n'
    'record stop | record status (close finalizes recording)\n'
    'workflow schema [action] | workflow validate <path> | workflow run <path>\n'
    'workflow: --format json|yaml --inputs <path> --inputs-format json|yaml\n'
    'validate --check-inputs checks bindings without connecting. stdin (-) requires format.\n'
    'sensitive forbids defaults; snapshots may reveal values displayed by the app.\n'
    'Workflow stops on failure; completed steps must not be replayed automatically.\n'
    'Selectors: --key <value> | --identifier <value> | --text <value> | --type <value>\n'
    'Common options work before or after commands. Use -- for literal arguments.\n'
    'Session/timeout validate only the selected CLI, environment or default value.\n'
    'Empty or invalid selected values are INVALID_ARGUMENT; overridden environment values are ignored.\n'
    'Additional Flutter commands (see docs/ja/cli-parity.ja.md):\n'
    'snapshot --interactive --compact --depth <n> | get value | is enabled|checked\n'
    'find role|label|placeholder|text|key|identifier|type <value> [action] [input] [--exact] [--name <label>]\n'
    'find first|last <selector> [action] | find nth <index> <selector> [action]\n'
    'click|dblclick|focus|hover|check|uncheck|scrollintoview <ref|selector>\n'
    'type|select <ref|selector> <input> | press <key-combination> | keydown|keyup <key>\n'
    'keyboard press|type|inserttext <input> | clipboard read|write <text>|copy|paste\n'
    'drag <from-ref> <to-ref> | drag --from-key <key> --to-key <key>\n'
    'wait <milliseconds|ref> | screenshot <ref|selector> [path]\n'
    'diff snapshot|screenshot --baseline <path> [--threshold <0-255> --output <path>]\n'
    'record restart <path> --platform <platform> --device <id> | record start/restart --fps <1-60>\n'
    'device list [--platform ios|android] | batch <JSON-file|->\n'
    'state save|load <path> (connection only) | confirm|deny <confirmation-id>\n'
    'doctor --quick|--offline|--fix | install|upgrade [--source <package-directory>] <bin-directory>';

const skillsUsage =
    '''marionette-agent skills - List and retrieve bundled skill content

Usage: marionette-agent skills [subcommand] [options]

  list                       List available skills (default)
  get <name> [name...]        Output SKILL.md including frontmatter
  get <name> --full           Include references/ and templates/ files
  get --all                  Output every visible skill (accepts --full)
  path [name]                Print skill directory paths; does not download

  --json                     Output structured JSON
  --help, -h                 Show this help

Examples:
  marionette-agent skills get core
  marionette-agent skills get core --full
  marionette-agent skills get simulator-verify --full
  marionette-agent skills get --all
  marionette-agent skills path core
  marionette-agent skills list --json

Environment:
  MARIONETTE_AGENT_SKILLS_DIR  Override with one existing skills directory

Bundled content matches the installed CLI. No daemon or connection is required.
''';
