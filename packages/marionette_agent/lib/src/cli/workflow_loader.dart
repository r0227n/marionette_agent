import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
// Internal scanner isolated here; pinned yaml and subset tests guard upgrades.
// ignore: implementation_imports
import 'package:yaml/src/scanner.dart';
// ignore: implementation_imports
import 'package:yaml/src/token.dart';

import '../protocol/protocol.dart';
import '../workflow/model.dart';

String workflowFormat(String file, String? explicit) {
  if (explicit != null) {
    if (!['json', 'yaml'].contains(explicit)) invalid();
    return explicit;
  }
  return switch (path.extension(file).toLowerCase()) {
    '.json' => 'json',
    '.yaml' || '.yml' => 'yaml',
    _ => invalid('An explicit input format is required'),
  };
}

Future<Object?> loadWorkflowFile(
  String file,
  String format,
  DateTime deadline,
) async {
  try {
    if (file == '-' && stdin.hasTerminal) invalid('stdin must be redirected');
    if (!deadline.isAfter(DateTime.now())) {
      throw const AgentError('TIMEOUT', 'Input deadline exceeded');
    }
    final stream = file == '-' ? stdin : File(file).openRead();
    final bytes = <int>[];
    final chunks = StreamIterator(stream);
    try {
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw const AgentError('TIMEOUT', 'Input deadline exceeded');
        }
        if (!await chunks.moveNext().timeout(remaining)) break;
        final chunk = chunks.current;
        if (bytes.length + chunk.length > workflowFileLimit) {
          invalid('Workflow file exceeds 1 MiB');
        }
        bytes.addAll(chunk);
      }
    } finally {
      await chunks.cancel();
    }
    if (!deadline.isAfter(DateTime.now())) {
      throw const AgentError('TIMEOUT', 'Input deadline exceeded');
    }
    final result = parseWorkflowText(utf8.decode(bytes), format);
    if (!deadline.isAfter(DateTime.now())) {
      throw const AgentError('TIMEOUT', 'Input deadline exceeded');
    }
    return result;
  } on FileSystemException {
    throw const AgentError('IO_ERROR', 'Cannot read workflow input file');
  } on TimeoutException {
    throw const AgentError('TIMEOUT', 'Input deadline exceeded');
  } on FormatException {
    invalid('Invalid UTF-8 input');
  }
}

Object? parseWorkflowText(String source, String format) {
  if (utf8.encode(source).length > workflowFileLimit) {
    invalid('Workflow file exceeds 1 MiB');
  }
  if (source.startsWith('\uFEFF')) source = source.substring(1);
  if (source.trim().isEmpty) invalid('Empty workflow input');
  try {
    final Object? result;
    if (format == 'json') {
      result = _JsonReader(source).parse();
    } else if (format == 'yaml') {
      final oldWarning = yamlWarningCallback;
      yamlWarningCallback = (_, [_]) => invalid('Unsupported YAML directive');
      try {
        final scanner = Scanner(source);
        var depth = 0;
        while (true) {
          final token = scanner.scan();
          if ([
            TokenType.tag,
            TokenType.tagDirective,
            TokenType.anchor,
            TokenType.alias,
          ].contains(token.type)) {
            invalid('Unsupported YAML feature');
          }
          if (token is VersionDirectiveToken &&
              (token.major != 1 || token.minor != 2)) {
            invalid('YAML 1.2 is required');
          }
          if ([
            TokenType.blockSequenceStart,
            TokenType.blockMappingStart,
            TokenType.flowSequenceStart,
            TokenType.flowMappingStart,
          ].contains(token.type)) {
            if (++depth > 32) invalid('Workflow nesting limit exceeded');
          }
          if ([
            TokenType.blockEnd,
            TokenType.flowSequenceEnd,
            TokenType.flowMappingEnd,
          ].contains(token.type)) {
            depth--;
          }
          if (token.type == TokenType.streamEnd) break;
        }
        result = _copyYaml(loadYaml(source));
      } finally {
        yamlWarningCallback = oldWarning;
      }
    } else {
      invalid('Unknown input format');
    }
    checkTree(result);
    return result;
  } on YamlException {
    invalid('Invalid YAML input');
  } on FormatException {
    invalid('Invalid JSON input');
  }
}

Object? _copyYaml(Object? value) {
  if (value is Map) {
    final result = <String, Object?>{};
    for (final e in value.entries) {
      if (e.key is! String || e.key == '<<' || result.containsKey(e.key)) {
        invalid('Invalid YAML mapping key');
      }
      result[e.key as String] = _copyYaml(e.value);
    }
    return result;
  }
  if (value is List) return [for (final item in value) _copyYaml(item)];
  return value;
}

// Retain duplicate keys before decoding. dart:convert owns scalar syntax.
class _JsonReader {
  _JsonReader(this.source);
  final String source;
  int offset = 0;
  void ws() {
    while (offset < source.length && ' \r\n\t'.contains(source[offset])) {
      offset++;
    }
  }

  bool take(String c) {
    ws();
    if (offset < source.length && source[offset] == c) {
      offset++;
      return true;
    }
    return false;
  }

  void need(String c) {
    if (!take(c)) throw const FormatException();
  }

  Object? parse() {
    final result = value(0);
    ws();
    if (offset != source.length) throw const FormatException();
    return result;
  }

  Object? value(int depth) {
    ws();
    if (offset >= source.length) throw const FormatException();
    if (source[offset] == '{') {
      if (depth >= 32) invalid('Workflow nesting limit exceeded');
      offset++;
      final map = <String, Object?>{};
      if (take('}')) return map;
      do {
        ws();
        if (offset >= source.length || source[offset] != '"') {
          throw const FormatException();
        }
        final key = string();
        need(':');
        if (map.containsKey(key)) invalid('Duplicate JSON key');
        map[key] = value(depth + 1);
      } while (take(','));
      need('}');
      return map;
    }
    if (source[offset] == '[') {
      if (depth >= 32) invalid('Workflow nesting limit exceeded');
      offset++;
      final list = <Object?>[];
      if (take(']')) return list;
      do {
        list.add(value(depth + 1));
      } while (take(','));
      need(']');
      return list;
    }
    if (source[offset] == '"') return string();
    final start = offset;
    while (offset < source.length && !' \t\r\n,]}'.contains(source[offset])) {
      offset++;
    }
    return jsonDecode(source.substring(start, offset));
  }

  String string() {
    final start = offset++;
    while (offset < source.length) {
      final char = source[offset++];
      if (char == '\\') {
        offset++;
        continue;
      }
      if (char == '"') {
        return jsonDecode(source.substring(start, offset)) as String;
      }
    }
    throw const FormatException();
  }
}
