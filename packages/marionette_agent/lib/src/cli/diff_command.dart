import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
// ignore: implementation_imports
import 'package:image/src/formats/png_decoder.dart';
// ignore: implementation_imports
import 'package:image/src/formats/png_encoder.dart';
// ignore: implementation_imports
import 'package:image/src/image/image.dart';

import '../protocol/protocol.dart';
import 'artifact_writer.dart';
import 'parser.dart';

CliCommand diffCommand() => CliCommand(
  ArgParser()
    ..addCommand(
      'snapshot',
      ArgParser()..addOption('baseline', mandatory: true),
    )
    ..addCommand(
      'screenshot',
      ArgParser()
        ..addOption('baseline', mandatory: true)
        ..addOption('output')
        ..addOption('threshold', defaultsTo: '0'),
    ),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty || child == null || child.rest.isNotEmpty) {
      invalid('Usage: diff snapshot|screenshot --baseline <path>');
    }
    final path = child.option('baseline')!;
    if (path.isEmpty) invalid('Baseline path must not be empty');
    return {
      'action': child.name,
      'baseline': path,
      if (child.name == 'screenshot') ...{
        'output': child.option('output'),
        'threshold': parseThreshold(child.option('threshold')!),
      },
    };
  },
);

int parseThreshold(String value) {
  final threshold = int.tryParse(value);
  if (threshold == null || threshold < 0 || threshold > 255) {
    invalid('Threshold must be an integer from 0 to 255');
  }
  return threshold;
}

Future<Uint8List> readBaseline(String path, DateTime deadline) async {
  try {
    final stat = await FileStat.stat(path);
    if (stat.type != FileSystemEntityType.file ||
        stat.size > 32 * 1024 * 1024) {
      invalid('Baseline must be a regular file of at most 32 MiB');
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw const AgentError('TIMEOUT', 'Baseline deadline exceeded');
    }
    return await File(path).readAsBytes().timeout(remaining);
  } on AgentError {
    rethrow;
  } on TimeoutException {
    throw const AgentError('TIMEOUT', 'Baseline deadline exceeded');
  } catch (_) {
    throw const AgentError('IO_ERROR', 'Cannot read baseline');
  }
}

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
    final remaining = next.toList();
    final removed = <Json>[];
    for (final row in old) {
      check();
      final index = remaining.indexWhere(
        (other) => const DeepCollectionEquality().equals(row, other),
      );
      if (index < 0) {
        removed.add(row);
      } else {
        remaining.removeAt(index);
      }
    }
    return {
      'changed': removed.isNotEmpty || remaining.isNotEmpty,
      'added': remaining,
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
