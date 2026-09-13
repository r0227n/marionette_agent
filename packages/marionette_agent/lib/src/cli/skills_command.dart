import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../protocol/protocol.dart';
import 'parser.dart';

const skillDirectories = ['skills', 'skill-data'];
const skillsUsage =
    '''marionette-agent skills - List and retrieve bundled skill content

Usage: marionette-agent skills [subcommand] [options]

  list                       List available skills (default)
  get <name> [name...]        Output SKILL.md including frontmatter
  get <name> --full           Include references/ and templates/ files
  get --all                  Output every visible skill (accepts --full)
  path [name]                Print skill directory paths; does not download

  --json                     Output structured JSON
  --help, -h                 Show this help

Examples:
  marionette-agent skills get core
  marionette-agent skills get core --full
  marionette-agent skills get simulator-verify --full
  marionette-agent skills get --all
  marionette-agent skills path core
  marionette-agent skills list --json

Environment:
  MARIONETTE_AGENT_SKILLS_DIR  Override with one existing skills directory

Bundled content matches the installed CLI. No daemon or connection is required.
''';

CliCommand skillsCommand() => CliCommand(
  ArgParser()
    ..addCommand('list')
    ..addCommand(
      'get',
      ArgParser()
        ..addFlag('full', negatable: false)
        ..addFlag('all', negatable: false),
    )
    ..addCommand('path'),
  (args) {
    final child = args.command;
    if (args.rest.isNotEmpty) invalid(skillsUsage);
    switch (child?.name) {
      case null:
      case 'list':
        if (child != null) CliParser.noArguments(child);
        return {'action': 'list'};
      case 'get':
        if (child!.rest.isEmpty && !child.flag('all')) {
          invalid(
            'No skill name provided. Usage: marionette-agent skills get <name>',
          );
        }
        return {
          'action': 'get',
          'names': child.rest,
          'all': child.flag('all'),
          'full': child.flag('full'),
        };
      case 'path':
        if (child!.rest.length > 1) {
          invalid('Usage: marionette-agent skills path [name]');
        }
        return {'action': 'path', 'name': child.rest.firstOrNull};
      default:
        invalid(skillsUsage);
    }
  },
);

/// Resolve installed assets from the executable, or Dart assets from the package.
/// Never use the caller's cwd to discover a different package's instructions.
Future<List<Directory>> findSkillsDirectories({
  Map<String, String>? environment,
  String? executable,
  Uri? packageUri,
  bool resolvePackage = true,
  String bundle = const String.fromEnvironment('MARIONETTE_AGENT_SKILL_BUNDLE'),
}) async {
  final override =
      (environment ?? Platform.environment)['MARIONETTE_AGENT_SKILLS_DIR'];
  if (override != null && Directory(override).existsSync()) {
    return [Directory(override)];
  }
  var exe = executable ?? Platform.resolvedExecutable;
  try {
    exe = File(exe).resolveSymbolicLinksSync();
  } on FileSystemException {
    // Nonexistent fixture paths can still describe a distribution layout.
  }
  List<Directory> at(String root) => [
    for (final name in skillDirectories)
      if (Directory(p.join(root, name)).existsSync())
        Directory(p.normalize(p.join(root, name))),
  ];
  if (bundle.isNotEmpty) {
    // install/upgrade binds each executable to its own immutable asset version.
    return at(p.join(p.dirname(exe), bundle));
  }
  String? rootFrom(String start) {
    var dir = p.absolute(start);
    while (true) {
      if (Directory(p.join(dir, 'skills')).existsSync()) return dir;
      final parent = p.dirname(dir);
      if (parent == dir) return null;
      dir = parent;
    }
  }

  final parent = p.dirname(exe);
  final adjacent = p.dirname(parent);
  final root = Directory(p.join(adjacent, 'skills')).existsSync()
      ? adjacent
      : rootFrom(parent);
  if (root != null) return at(root);
  packageUri ??= resolvePackage
      ? await Isolate.resolvePackageUri(
          Uri.parse('package:marionette_agent/marionette_agent.dart'),
        )
      : null;
  if (packageUri?.scheme == 'file') {
    return at(p.dirname(p.dirname(packageUri!.toFilePath())));
  }
  return [];
}

class BundledSkill {
  BundledSkill(
    this.name,
    this.description,
    this.hidden,
    this.directory,
    this.content,
  );
  final String name, description, content;
  final bool hidden;
  final Directory directory;
}

/// Match agent-browser's small frontmatter reader, including indented descriptions.
/// This intentionally does not interpret arbitrary YAML tags or values.
BundledSkill? parseSkill(Directory directory, String content) {
  final trimmed = content.trimLeft();
  if (!trimmed.startsWith('---')) return null;
  final end = trimmed.indexOf('\n---', 3);
  if (end < 0) return null;
  final lines = trimmed.substring(3, end).split('\n');
  String? name;
  var description = '';
  var hidden = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('name:')) {
      name = line.substring(5).trim();
    } else if (line.startsWith('description:')) {
      description = line.substring(12).trim();
      while (i + 1 < lines.length &&
          (lines[i + 1].startsWith('  ') || lines[i + 1].startsWith('\t'))) {
        description += ' ${lines[++i].trim()}';
      }
    } else if (line.startsWith('hidden:')) {
      hidden = ['true', 'yes'].contains(line.substring(7).trim());
    }
  }
  return name == null
      ? null
      : BundledSkill(name, description, hidden, directory, content);
}

/// Read-only catalog shared by list/get/path. Unreadable or invalid entries are skipped.
class SkillCatalog {
  SkillCatalog(this.directories, {this.deadline});
  final List<Directory> directories;
  final DateTime? deadline;

  void _check() {
    if (deadline != null && !deadline!.isAfter(DateTime.now())) {
      throw const AgentError('TIMEOUT', 'Skills reading deadline exceeded');
    }
  }

  List<FileSystemEntity> _entries(Directory directory) {
    _check();
    try {
      return directory.listSync();
    } on FileSystemException {
      return [];
    }
  }

  String? _read(String path) {
    _check();
    // Text resources only: opening a FIFO would block even a local command.
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
      return null;
    }
    try {
      final content = File(path).readAsStringSync();
      _check();
      return content;
    } on FileSystemException {
      return null;
    }
  }

  List<BundledSkill> discover() {
    final skills = <BundledSkill>[];
    for (final directory in directories) {
      for (final entry in _entries(directory)) {
        if (!Directory(entry.path).existsSync()) continue;
        final content = _read(p.join(entry.path, 'SKILL.md'));
        if (content == null) continue;
        final skill = parseSkill(Directory(entry.path), content);
        if (skill != null) skills.add(skill);
      }
    }
    // The second key preserves directory precedence for duplicate names.
    final indexed = skills.indexed.toList()
      ..sort((a, b) {
        final order = a.$2.name.compareTo(b.$2.name);
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    return indexed.map((entry) => entry.$2).toList();
  }

  List<Json> supplementary(BundledSkill skill) => [
    for (final subdir in ['references', 'templates'])
      for (final entry in (_entries(
        Directory(p.join(skill.directory.path, subdir)),
      )..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)))))
        if (_read(entry.path) case final String content)
          {'path': '$subdir/${p.basename(entry.path)}', 'content': content},
  ];

  SkillsOutput run(Json params) {
    _check();
    final output = _run(params);
    _check();
    return output;
  }

  SkillsOutput _run(Json params) {
    if (directories.isEmpty) {
      throw const AgentError(
        'IO_ERROR',
        'Skills directory not found. Set MARIONETTE_AGENT_SKILLS_DIR or reinstall the CLI with its bundled skills.',
      );
    }
    final action = params['action'];
    if (action == 'path' && params['name'] == null) {
      final paths = directories.map((d) => d.path).toList();
      return SkillsOutput({'paths': paths}, paths.join('\n'));
    }
    final skills = discover();
    BundledSkill named(String name) => skills.firstWhere(
      (skill) => skill.name == name,
      orElse: () =>
          throw AgentError('INVALID_ARGUMENT', 'Skill not found: $name'),
    );
    if (action == 'path') {
      final skill = named(params['name'] as String);
      return SkillsOutput({
        'name': skill.name,
        'path': skill.directory.path,
      }, skill.directory.path);
    }
    if (action == 'list') {
      final visible = skills.where((s) => !s.hidden).toList();
      final width = visible.fold(
        0,
        (n, s) => n > s.name.length ? n : s.name.length,
      );
      return SkillsOutput(
        [
          for (final s in visible)
            {'name': s.name, 'description': s.description},
        ],
        visible.isEmpty
            ? 'No skills found'
            : visible
                  .map(
                    (s) =>
                        '  ${s.name.padRight(width)}  ${_shortDescription(s.description)}',
                  )
                  .join('\n'),
      );
    }
    final targets = params['all'] == true
        ? skills.where((s) => !s.hidden).toList()
        : [
            for (final name in (params['names'] as List).cast<String>())
              named(name),
          ];
    if (targets.isEmpty) {
      invalid(
        'No skill name provided. Usage: marionette-agent skills get <name>',
      );
    }
    final items = <Json>[];
    final text = <String>[];
    for (final skill in targets) {
      final files = params['full'] == true ? supplementary(skill) : <Json>[];
      items.add({
        'name': skill.name,
        'content': skill.content,
        if (files.isNotEmpty) 'files': files,
      });
      text.add(
        [
          _newline(skill.content),
          for (final file in files)
            '\n--- ${file['path']} ---\n\n${_newline(file['content'] as String)}',
        ].join(),
      );
    }
    return SkillsOutput(items, text.join('\n---\n\n'));
  }
}

String _newline(String text) => text.endsWith('\n') ? text : '$text\n';

String _shortDescription(String text) {
  if (utf8.encode(text).length <= 70) return text;
  var bytes = 0;
  final chars = <int>[];
  for (final rune in text.runes) {
    bytes += utf8.encode(String.fromCharCode(rune)).length;
    if (bytes > 70) break;
    chars.add(rune);
  }
  final prefix = String.fromCharCodes(chars);
  final space = prefix.lastIndexOf(' ');
  return '${space < 0 ? prefix : prefix.substring(0, space)}...';
}

/// Compatibility envelope is intentionally local, never an IPC Result.
class SkillsOutput {
  SkillsOutput(this.data, this.text);
  final Object data;
  final String text;
  String render(bool json) =>
      json ? jsonEncode({'success': true, 'data': data}) : text;
}
