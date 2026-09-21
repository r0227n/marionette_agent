import 'package:args/args.dart';

import '../../protocol/protocol.dart';
import '../command.dart';

CliCommand installCommand() =>
    CliCommand(ArgParser()..addOption('source'), (args) {
      if (args.rest.length != 1 || args.rest.single.isEmpty) {
        invalid(
          'Usage: install|upgrade [--source <package-directory>] <existing-bin-directory>',
        );
      }
      return {'directory': args.rest.single, 'source': args.option('source')};
    });

/// Compile the selected checkout. Never fetch code or modify the Flutter SDK.
