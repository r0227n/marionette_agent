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
