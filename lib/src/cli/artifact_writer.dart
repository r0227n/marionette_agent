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

import '../protocol/protocol.dart';
import 'common_options.dart';

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
  if (data.containsKey('crop') || data.containsKey('annotations')) {
    throw const AgentError(
      'UNSUPPORTED_CAPABILITY',
      'Screenshot crop and ref annotation were removed',
    );
  }
  if (destination != null) destination = format.destinationPath(destination);
  final payloads = data['images'];
  if (payloads is! List || payloads.isEmpty) {
    throw const AgentError('BACKEND_ERROR', 'No screenshots returned');
  }
  final images = <Uint8List>[];
  Json? capture;
  try {
    for (final value in payloads) {
      checkDeadline();
      if (value is! String) throw const FormatException();
      final bytes = base64Decode(value);
      final decoded = PngDecoder().decode(bytes);
      if (decoded == null) throw const FormatException();
      checkDeadline();
      images.add(bytes);
      if (data['capture'] case final Map metadata) {
        if (payloads.length != 1 ||
            data.containsKey('crop') ||
            data.containsKey('annotations')) {
          throw const AgentError(
            'UNSUPPORTED_CAPABILITY',
            'Native capture requires one unmodified device image',
          );
        }
        capture = {
          ...asJson(metadata),
          'pixelWidth': decoded.width,
          'pixelHeight': decoded.height,
          'orientation': decoded.width == decoded.height
              ? 'square'
              : decoded.width > decoded.height
              ? 'landscape'
              : 'portrait',
        };
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
  // Encode the acquired pixels as JPEG.
  if (format == ScreenshotFormat.jpeg) {
    try {
      for (var i = 0; i < images.length; i++) {
        checkDeadline();
        final decoded = PngDecoder().decode(images[i]);
        if (decoded == null) throw const FormatException();
        // Flatten into opaque RGB before encoding. This also handles grayscale
        // alpha, palette/16-bit PNGs and padded JPEG edge blocks consistently.
        final rgb = Image(width: decoded.width, height: decoded.height);
        // The pinned PNG decoder does not read eXIf. XCUIScreen uses that
        // chunk for landscape display; retain its orientation without rotating pixels.
        final orientation = _pngExifOrientation(images[i]);
        if (orientation != null) rgb.exif.imageIfd.orientation = orientation;
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
    return {'paths': paths, 'capture': ?capture};
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

// Read only the standard TIFF IFD0 orientation from a PNG eXIf chunk. Bounds
// checks keep malformed ancillary metadata from changing image persistence.
int? _pngExifOrientation(Uint8List png) {
  final bytes = ByteData.sublistView(png);
  for (var offset = 8; offset + 12 <= png.length;) {
    final length = bytes.getUint32(offset);
    if (length > png.length - offset - 12) return null;
    if (bytes.getUint32(offset + 4) == 0x65584966) {
      // eXIf
      final tiff = ByteData.sublistView(png, offset + 8, offset + 8 + length);
      if (tiff.lengthInBytes < 8) return null;
      final order = tiff.getUint16(0);
      if (order != 0x4949 && order != 0x4d4d) return null;
      final endian = order == 0x4949 ? Endian.little : Endian.big;
      if (tiff.getUint16(2, endian) != 42) return null;
      final ifd = tiff.getUint32(4, endian);
      if (ifd > tiff.lengthInBytes - 2) return null;
      final count = tiff.getUint16(ifd, endian);
      for (var i = 0; i < count; i++) {
        final entry = ifd + 2 + 12 * i;
        if (entry > tiff.lengthInBytes - 12) return null;
        if (tiff.getUint16(entry, endian) == 0x0112 &&
            tiff.getUint16(entry + 2, endian) == 3 &&
            tiff.getUint32(entry + 4, endian) == 1) {
          final value = tiff.getUint16(entry + 8, endian);
          return value >= 1 && value <= 8 ? value : null;
        }
      }
      return null;
    }
    offset += length + 12;
  }
  return null;
}
