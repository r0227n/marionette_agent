import 'dart:typed_data';

// Keep the pinned image 4.9.1 dependency narrow so other CLI commands do not
// compile every codec and filter during startup.
// ignore: implementation_imports
import 'package:image/src/color/color_uint8.dart' as img;
// ignore: implementation_imports
import 'package:image/src/draw/draw_rect.dart' as img;
// ignore: implementation_imports
import 'package:image/src/draw/draw_line.dart' as img;
// ignore: implementation_imports
import 'package:image/src/draw/fill_rect.dart' as img;
// ignore: implementation_imports
import 'package:image/src/formats/png_decoder.dart' as img;
// ignore: implementation_imports
import 'package:image/src/formats/png_encoder.dart' as img;

import '../protocol/protocol.dart';
import '../backend/screenshot_geometry.dart';

// A fixed 5x7 alphabet avoids loading a general XML/ZIP font parser for every
// CLI startup. Only these characters can occur in a validated public ref.
const _glyphs = <String, List<int>>{
  '@': [14, 17, 23, 21, 23, 16, 14],
  'e': [0, 0, 14, 17, 31, 16, 14],
  '0': [14, 17, 19, 21, 25, 17, 14],
  '1': [4, 12, 4, 4, 4, 4, 14],
  '2': [14, 17, 1, 2, 4, 8, 31],
  '3': [30, 1, 1, 14, 1, 1, 30],
  '4': [2, 6, 10, 18, 31, 2, 2],
  '5': [31, 16, 16, 30, 1, 1, 30],
  '6': [14, 16, 16, 30, 17, 17, 14],
  '7': [31, 1, 2, 4, 8, 8, 8],
  '8': [14, 17, 17, 14, 17, 17, 14],
  '9': [14, 17, 17, 15, 1, 1, 14],
};

class AnnotatedScreenshot {
  AnnotatedScreenshot(this.bytes, this.count, this.skipped);
  final Uint8List bytes;
  final int count;
  final List<Json> skipped;
}

AnnotatedScreenshot annotateScreenshot(
  Uint8List bytes,
  Json data,
  void Function() checkDeadline,
) {
  checkDeadline();
  final geometry = ScreenshotGeometry.decode(data['geometry']);
  final image = img.PngDecoder().decode(bytes);
  if (image == null) {
    throw const AgentError('BACKEND_ERROR', 'Invalid PNG screenshot');
  }
  if (image.width != geometry.width || image.height != geometry.height) {
    throw const AgentError(
      'UNSUPPORTED_CAPABILITY',
      'Screenshot dimensions do not match capture geometry',
    );
  }
  final annotation = data['annotations'];
  if (annotation is! Map ||
      annotation['generation'] is! int ||
      annotation['targets'] is! List) {
    throw const AgentError('BACKEND_ERROR', 'Invalid screenshot annotations');
  }
  final skipped = <Json>[];
  final labels = <({String ref, int x, int y, int width})>[];
  var count = 0;
  final color = img.ColorRgb8(220, 25, 80);
  for (final target in annotation['targets'] as List) {
    checkDeadline();
    if (target is! Map ||
        target['ref'] is! String ||
        !RegExp(r'^@e[1-9][0-9]*$').hasMatch(target['ref'] as String)) {
      throw const AgentError('BACKEND_ERROR', 'Invalid annotation ref');
    }
    final ref = target['ref'] as String;
    final bounds = target['bounds'];
    if (bounds is! Map ||
        [
          'x',
          'y',
          'width',
          'height',
        ].any((key) => bounds[key] is! num || !(bounds[key] as num).isFinite)) {
      skipped.add({'ref': ref, 'reason': 'missing_or_invalid_bounds'});
      continue;
    }
    final x = (bounds['x'] as num).toDouble();
    final y = (bounds['y'] as num).toDouble();
    final w = (bounds['width'] as num).toDouble();
    final h = (bounds['height'] as num).toDouble();
    if (x < 0 ||
        y < 0 ||
        w <= 0 ||
        h <= 0 ||
        x + w > geometry.logicalWidth ||
        y + h > geometry.logicalHeight) {
      skipped.add({'ref': ref, 'reason': 'bounds_outside_view'});
      continue;
    }
    final x1 = (x * geometry.width / geometry.logicalWidth).floor();
    final y1 = (y * geometry.height / geometry.logicalHeight).floor();
    final x2 = ((x + w) * geometry.width / geometry.logicalWidth).ceil() - 1;
    final y2 = ((y + h) * geometry.height / geometry.logicalHeight).ceil() - 1;
    final labelWidth = ref.length * 12 + 4;
    if (image.width < labelWidth || image.height < 20) {
      skipped.add({'ref': ref, 'reason': 'label_space_exhausted'});
      continue;
    }
    final labelX = x1.clamp(0, image.width - labelWidth);
    int? labelY;
    final initialY = y1.clamp(0, image.height - 20);
    for (var offset = 0; offset < image.height; offset += 22) {
      checkDeadline();
      final candidate = (initialY + offset) % (image.height - 19);
      if (labels.every(
        (label) =>
            labelX + labelWidth <= label.x ||
            label.x + label.width <= labelX ||
            candidate + 20 <= label.y ||
            label.y + 20 <= candidate,
      )) {
        labelY = candidate;
        break;
      }
    }
    if (labelY == null) {
      skipped.add({'ref': ref, 'reason': 'label_space_exhausted'});
      continue;
    }
    img.drawRect(
      image,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      color: color,
      thickness: 2,
    );
    if (labelX != x1 || labelY != y1) {
      img.drawLine(image, x1: x1, y1: y1, x2: labelX, y2: labelY, color: color);
    }
    labels.add((ref: ref, x: labelX, y: labelY, width: labelWidth));
    count++;
  }
  // Draw labels last so later element borders cannot obscure earlier labels.
  for (final label in labels) {
    checkDeadline();
    img.fillRect(
      image,
      x1: label.x,
      y1: label.y,
      x2: label.x + label.width - 1,
      y2: label.y + 19,
      color: color,
    );
    for (var i = 0; i < label.ref.length; i++) {
      final glyph = _glyphs[label.ref[i]]!;
      for (var row = 0; row < 7; row++) {
        for (var column = 0; column < 5; column++) {
          if ((glyph[row] & (1 << (4 - column))) == 0) continue;
          final x = label.x + 2 + i * 12 + column * 2;
          final y = label.y + 3 + row * 2;
          img.fillRect(
            image,
            x1: x,
            y1: y,
            x2: x + 1,
            y2: y + 1,
            color: img.ColorRgb8(255, 255, 255),
          );
        }
      }
    }
  }
  checkDeadline();
  final encoded = img.PngEncoder().encode(image);
  checkDeadline();
  return AnnotatedScreenshot(encoded, count, skipped);
}
