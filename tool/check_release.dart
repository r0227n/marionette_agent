import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:marionette_agent/src/protocol/protocol.dart' as protocol;

void main() {
  for (final path in [
    'pubspec.yaml',
    'packages/marionette_agent_util/pubspec.yaml',
    'example/pubspec.yaml',
  ]) {
    final spec = loadYaml(File(path).readAsStringSync()) as YamlMap;
    if ((spec['version'] as String).split('+').first != protocol.version ||
        spec['publish_to'] != 'none') {
      throw StateError(
        '$path must match CLI ${protocol.version} and remain unpublished',
      );
    }
  }
  if (!File('CHANGELOG.md')
      .readAsStringSync()
      .contains('## ${protocol.version}')) {
    throw StateError('Missing changelog for ${protocol.version}');
  }
  stdout.writeln(
    'CLI/util/changelog aligned at ${protocol.version}; pub.dev disabled.',
  );
}
