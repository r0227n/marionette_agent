import 'dart:convert';
import 'dart:collection';
import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
// ignore: implementation_imports
import 'package:image/src/formats/png_decoder.dart';
// ignore: implementation_imports
import 'package:image/src/formats/png_encoder.dart';
// ignore: implementation_imports
import 'package:image/src/image/image.dart';

import '../protocol/protocol.dart';
import 'artifact_writer.dart';

Future<Json> compareObservation(
  Json params,
  Uint8List baseline,
  Json current,
  DateTime deadline,
) async {
  void check() {
    if (!deadline.isAfter(DateTime.now())) {
      throw const AgentError('TIMEOUT', 'Comparison deadline exceeded');
    }
  }

  check();
  if (params['action'] == 'snapshot') {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(baseline));
    } catch (_) {
      invalid('Baseline must contain a JSON snapshot');
    }
    if (decoded is Map && decoded['data'] is Map) decoded = decoded['data'];
    if (decoded is! Map ||
        decoded['elements'] is! List ||
        current['elements'] is! List) {
      invalid('Baseline must contain snapshot elements');
    }
    List<Json> rows(List items) => items.map((item) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        invalid('Invalid snapshot baseline element');
      }
      return Map<String, Object?>.from(item)
        ..remove('ref')
        ..remove('reason');
    }).toList();
    final old = rows(decoded['elements'] as List);
    final next = rows(current['elements'] as List);
    const equality = DeepCollectionEquality();
    final counts = HashMap<Json, int>(
      equals: equality.equals,
      hashCode: equality.hash,
    );
    for (final row in next) {
      check();
      counts[row] = (counts[row] ?? 0) + 1;
    }
    final removed = <Json>[];
    for (final row in old) {
      check();
      final count = counts[row] ?? 0;
      if (count == 0) {
        removed.add(row);
      } else {
        counts[row] = count - 1;
      }
    }
    final added = <Json>[];
    for (final row in next) {
      check();
      final count = counts[row] ?? 0;
      if (count > 0) {
        added.add(row);
        counts[row] = count - 1;
      }
    }
    return {
      'changed': removed.isNotEmpty || added.isNotEmpty,
      'added': added,
      'removed': removed,
      if (current['generation'] != null) 'generation': current['generation'],
    };
  }
  final payloads = current['images'];
  if (payloads is! List || payloads.length != 1 || payloads.single is! String) {
    throw const AgentError(
      'UNSUPPORTED_CAPABILITY',
      'Screenshot diff requires one image',
    );
  }
  final Image? before, after;
  try {
    before = PngDecoder().decode(baseline);
    after = PngDecoder().decode(base64Decode(payloads.single as String));
  } catch (_) {
    invalid('Screenshot diff requires valid PNG images');
  }
  if (before == null || after == null) {
    invalid('Screenshot diff requires valid PNG images');
  }
  if (before.width != after.width || before.height != after.height) {
    invalid('Screenshot dimensions differ');
  }
  final diff = Image(width: after.width, height: after.height, numChannels: 4);
  var count = 0;
  final threshold = params['threshold'] as int;
  for (var y = 0; y < after.height; y++) {
    check();
    for (var x = 0; x < after.width; x++) {
      final a = before.getPixel(x, y), b = after.getPixel(x, y);
      final changed = [
        (a.rNormalized - b.rNormalized).abs(),
        (a.gNormalized - b.gNormalized).abs(),
        (a.bNormalized - b.bNormalized).abs(),
        (a.aNormalized - b.aNormalized).abs(),
      ].any((delta) => delta * 255 > threshold);
      if (changed) {
        count++;
        diff.setPixelRgba(x, y, 255, 0, 80, 255);
      } else {
        diff.setPixelRgba(
          x,
          y,
          b.rNormalized * 255,
          b.gNormalized * 255,
          b.bNormalized * 255,
          80,
        );
      }
    }
  }
  final result = <String, Object?>{
    'changed': count != 0,
    'changedPixels': count,
    'totalPixels': after.width * after.height,
    'ratio': count / (after.width * after.height),
    'threshold': threshold,
  };
  if (params['output'] != null) {
    result.addAll(
      await saveScreenshots(
        {
          'images': [base64Encode(PngEncoder().encode(diff))],
        },
        params['output'] as String,
        deadline,
      ),
    );
  }
  check();
  return result;
}
