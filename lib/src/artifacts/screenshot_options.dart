import 'package:path/path.dart' as p;

import '../protocol/protocol.dart';
import 'screenshot_format.dart';

/// Already resolved by the caller. Workflow persistence runs on the daemon
/// before proceeding to the next action, using the same exclusive writer.
class ScreenshotOptions {
  const ScreenshotOptions(this.format, this.quality, this.directory);
  final ScreenshotFormat format;
  final int quality;
  final String? directory;
  factory ScreenshotOptions.decode(Object? raw) {
    if (raw != null && raw is! Map<String, Object?>) {
      invalid('Invalid screenshot output options');
    }
    final data = raw == null ? <String, Object?>{} : asJson(raw);
    if (data.keys.any(
      (key) => !{'format', 'quality', 'directory'}.contains(key),
    )) {
      invalid('Invalid screenshot output options');
    }
    final format = data.containsKey('format') ? data['format'] : 'png';
    final quality = data.containsKey('quality') ? data['quality'] : 90;
    final directory = data['directory'];
    if (!['png', 'jpeg'].contains(format) ||
        quality is! int ||
        quality < 0 ||
        quality > 100 ||
        (format != 'jpeg' && data.containsKey('quality')) ||
        (data.containsKey('directory') &&
            (directory is! String ||
                directory.contains('\u0000') ||
                !p.isAbsolute(directory)))) {
      invalid('Invalid screenshot output options');
    }
    return ScreenshotOptions(
      ScreenshotFormat.values.byName(format as String),
      quality,
      directory as String?,
    );
  }
  void validateDestination(Object? path) {
    if (path == null) return;
    if (path is! String || path.contains('\u0000') || !p.isAbsolute(path)) {
      invalid('Workflow screenshot path must be resolved by the caller');
    }
    format.destinationPath(path);
  }
}
