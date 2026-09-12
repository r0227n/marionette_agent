import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// image is pinned to 4.9.1: its public barrel loads every codec/filter.
// Keep these internal APIs at this boundary; validate codec tests before upgrades.
// ignore: implementation_imports
import 'package:image/src/formats/jpeg_encoder.dart' show JpegEncoder;
// ignore: implementation_imports
import 'package:image/src/formats/png_decoder.dart' show PngDecoder;
// ignore: implementation_imports
import 'package:image/src/image/image.dart' show Image;
import 'package:path/path.dart' as p;

import '../protocol/protocol.dart';
import 'common_options.dart';

/// Decode before writing, reserve each destination exclusively, and roll back
/// this request's files on failure. Existing files are not normally overwritten.
Future<Json> saveScreenshots(
  Json data,
  String? destination,
  DateTime deadline, {
  ScreenshotFormat format = ScreenshotFormat.png,
  int quality = CommonOptions.defaultScreenshotQuality,
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  void checkDeadline() {
    if (!clock().isBefore(deadline)) {
      throw const AgentError('TIMEOUT', 'Screenshot saving deadline exceeded');
    }
  }

  checkDeadline();
  if (destination != null) destination = format.destinationPath(destination);
  final payloads = data['images'];
  if (payloads is! List || payloads.isEmpty) {
    throw const AgentError('BACKEND_ERROR', 'No screenshots returned');
  }
  final images = <Uint8List>[];
  try {
    for (final value in payloads) {
      checkDeadline();
      if (value is! String) throw const FormatException();
      final bytes = base64Decode(value);
      final decoded = PngDecoder().decode(bytes);
      if (decoded == null) throw const FormatException();
      checkDeadline();
      if (format == ScreenshotFormat.jpeg) {
        // Flatten into opaque RGB before encoding. This also handles grayscale
        // alpha, palette/16-bit PNGs and padded JPEG edge blocks consistently.
        final rgb = Image(width: decoded.width, height: decoded.height);
        for (final pixel in decoded) {
          if (pixel.x == 0 && pixel.y % 256 == 0) checkDeadline();
          final alpha = pixel.aNormalized;
          final white = 1 - alpha;
          final red = pixel.rNormalized;
          final green = pixel.length < 3 ? red : pixel.gNormalized;
          final blue = pixel.length < 3 ? red : pixel.bNormalized;
          rgb.setPixelRgb(
            pixel.x,
            pixel.y,
            (255 * (red * alpha + white)).round(),
            (255 * (green * alpha + white)).round(),
            (255 * (blue * alpha + white)).round(),
          );
        }
        checkDeadline();
        images.add(JpegEncoder(quality: quality).encode(rgb));
      } else {
        images.add(bytes);
      }
      // Synchronous codecs cannot be interrupted; never publish late output.
      checkDeadline();
    }
  } on AgentError {
    rethrow;
  } catch (_) {
    throw const AgentError(
      'BACKEND_ERROR',
      'Cannot decode or convert PNG screenshot',
    );
  }
  Directory? temporary;
  final created = <File>[];
  try {
    checkDeadline();
    if (destination == null) {
      temporary = await Directory.systemTemp.createTemp(
        'marionette-screenshot-',
      );
    }
    final base = p.normalize(
      p.absolute(
        destination ?? p.join(temporary!.path, 'screen${format.extension}'),
      ),
    );
    final paths = List.generate(
      images.length,
      (i) => images.length == 1
          ? base
          : p.join(
              p.dirname(base),
              '${p.basenameWithoutExtension(base)}-${i + 1}${p.extension(base)}',
            ),
    );
    // Reserve every path before writing any image. This refuses destinations
    // that already exist during normal use, including directories and symlinks.
    for (final path in paths) {
      checkDeadline();
      final file = File(path);
      await file.create(exclusive: true);
      created.add(file);
    }
    for (var i = 0; i < created.length; i++) {
      checkDeadline();
      await created[i].writeAsBytes(images[i], flush: true);
    }
    checkDeadline();
    return {'paths': paths};
  } catch (error) {
    for (final file in created) {
      try {
        await file.delete();
      } catch (_) {
        /* Preserve original error. */
      }
    }
    if (temporary != null) {
      try {
        await temporary.delete();
      } catch (_) {
        /* Preserve original error. */
      }
    }
    if (error is AgentError) rethrow;
    throw const AgentError(
      'IO_ERROR',
      'Cannot save screenshots; check destination, permissions and existing files',
    );
  }
}
