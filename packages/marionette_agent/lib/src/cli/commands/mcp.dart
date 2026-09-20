import 'package:args/args.dart';

import '../../mcp/catalog.dart';
import '../command.dart';

CliCommand mcpCommand() => CliCommand(
  ArgParser()..addOption(
    'tools',
    defaultsTo: 'core',
    help: 'Comma-separated MCP profiles: ${mcpProfiles.join(', ')}',
  ),
  (args) {
    noArguments(args);
    return {'profiles': parseMcpProfiles(args.option('tools')!)};
  },
);
