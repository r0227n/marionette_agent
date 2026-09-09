import 'dart:io';

import 'package:path/path.dart' as p;

/// Keep screenshots from each run separate, even when the report path is reused.
Future<Directory> createEvidenceDirectory(String report, String prefix) async {
  final parent = Directory(p.dirname(p.absolute(report)));
  await parent.create(recursive: true);
  return parent.createTemp('$prefix-');
}
