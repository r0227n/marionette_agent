import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

// ignore: implementation_imports
import 'package:image/src/formats/png_encoder.dart' show PngEncoder;
// ignore: implementation_imports
import 'package:image/src/transform/copy_crop.dart' show copyCrop;

import '../backend/screenshot_geometry.dart';
import '../protocol/protocol.dart';
import 'common_options.dart';
import 'screenshot_annotation.dart';

/// Decode before writing, reserve each destination exclusively, and roll back
/// this request's files on failure. Existing files are not normally overwritten.
Future<Json> saveScreenshots(
  Json data,
  String? destination,
  DateTime deadline, {
  String? screenshotDir,
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
  AnnotatedScreenshot? annotated;
  try {
    for (final value in payloads) {
      checkDeadline();
      if (value is! String) throw const FormatException();
      final bytes = base64Decode(value);
      final decoded = PngDecoder().decode(bytes);
      if (decoded == null) throw const FormatException();
      checkDeadline();
      images.add(bytes);
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
  if (data.containsKey('crop')) {
    final geometry = ScreenshotGeometry.decode(data['geometry']);
    final bounds = data['crop'];
    if (images.length != 1 ||
        bounds is! Map ||
        [
          'x',
          'y',
          'width',
          'height',
        ].any((key) => bounds[key] is! num || !(bounds[key] as num).isFinite)) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Crop requires one mapped image and finite target bounds',
      );
    }
    final x = (bounds['x'] as num).toDouble(),
        y = (bounds['y'] as num).toDouble();
    final w = (bounds['width'] as num).toDouble(),
        h = (bounds['height'] as num).toDouble();
    final image = PngDecoder().decode(images.single)!;
    if (image.width != geometry.width ||
        image.height != geometry.height ||
        x < 0 ||
        y < 0 ||
        w <= 0 ||
        h <= 0 ||
        x + w > geometry.logicalWidth ||
        y + h > geometry.logicalHeight) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Target bounds must be wholly inside the mapped view',
      );
    }
    final left = (x * image.width / geometry.logicalWidth).floor();
    final top = (y * image.height / geometry.logicalHeight).floor();
    final right = ((x + w) * image.width / geometry.logicalWidth).ceil();
    final bottom = ((y + h) * image.height / geometry.logicalHeight).ceil();
    images[0] = PngEncoder().encode(
      copyCrop(
        image,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      ),
    );
    checkDeadline();
  }
  if (data.containsKey('annotations')) {
    if (images.length != 1) {
      throw const AgentError(
        'UNSUPPORTED_CAPABILITY',
        'Multiple screenshot view correspondence is not supported',
      );
    }
    annotated = annotateScreenshot(images.single, data, checkDeadline);
    images[0] = annotated.bytes;
  }
  // Annotation consumes mapped PNG pixels; encode the final pixels as JPEG.
  if (format == ScreenshotFormat.jpeg) {
    try {
      for (var i = 0; i < images.length; i++) {
        checkDeadline();
        final decoded = PngDecoder().decode(images[i]);
        if (decoded == null) throw const FormatException();
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
        images[i] = JpegEncoder(quality: quality).encode(rgb);
        checkDeadline();
      }
    } on AgentError {
      rethrow;
    } catch (_) {
      throw const AgentError('BACKEND_ERROR', 'Cannot convert PNG screenshot');
    }
  }
  Directory? temporary;
  final created = <File>[];
  try {
    checkDeadline();
    String? generated;
    if (destination == null) {
      if (screenshotDir == null) {
        temporary = await Directory.systemTemp.createTemp(
          'marionette-screenshot-',
        );
        generated = p.join(temporary.path, 'screen${format.extension}');
      } else {
        final directory = p.normalize(p.absolute(screenshotDir));
        if (await FileSystemEntity.type(directory, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw const AgentError(
            'IO_ERROR',
            'Screenshot directory must exist and must not be a symlink',
          );
        }
        final random = Random.secure();
        final token = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        generated = p.join(directory, 'screen-$token${format.extension}');
      }
    }
    final base = p.normalize(p.absolute(destination ?? generated!));
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
    return {
      'paths': paths,
      if (data.containsKey('crop')) 'cropped': true,
      if (annotated != null) ...{
        'annotated': true,
        'generation': (data['annotations'] as Map)['generation'],
        'annotationCount': annotated.count,
        'skippedAnnotations': annotated.skipped,
      },
    };
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
