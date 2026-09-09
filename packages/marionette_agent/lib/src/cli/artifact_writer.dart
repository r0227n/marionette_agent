import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// image is pinned to 4.9.1: its public barrel loads every codec/filter.
// Keep this internal API at this boundary; validate PNG tests before upgrades.
// ignore: implementation_imports
import 'package:image/src/formats/png_decoder.dart' show PngDecoder;
import 'package:path/path.dart' as p;

import '../protocol/protocol.dart';

/// Decode before writing, reserve each destination exclusively, and roll back
/// this request's files on failure. Existing files are never overwritten.
Future<Json> saveScreenshots(
  Json data,
  String? destination,
  DateTime deadline,
) async {
  void checkDeadline() {
    if (!DateTime.now().isBefore(deadline)) {
      throw const AgentError('TIMEOUT', 'Screenshot saving deadline exceeded');
    }
  }

  checkDeadline();
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
      if (PngDecoder().decode(bytes) == null) throw const FormatException();
      images.add(bytes);
    }
  } on AgentError {
    rethrow;
  } catch (_) {
    throw const AgentError('BACKEND_ERROR', 'Invalid PNG screenshot');
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
      p.absolute(destination ?? p.join(temporary!.path, 'screen.png')),
    );
    final paths = List.generate(
      images.length,
      (i) => images.length == 1
          ? base
          : p.join(
              p.dirname(base),
              '${p.basenameWithoutExtension(base)}-${i + 1}${p.extension(base).isEmpty ? '.png' : p.extension(base)}',
            ),
    );
    // Reserve every path before writing any image; exclusive creation also
    // refuses directories, symlinks and concurrent competing writers.
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
