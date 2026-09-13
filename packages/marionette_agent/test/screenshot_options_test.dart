import 'package:marionette_agent/src/cli/common_options.dart';
import 'package:marionette_agent/src/cli/parser.dart';
import 'package:marionette_agent/src/protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  final parser = CliParser();
  final invalidArgument = throwsA(
    isA<AgentError>().having((e) => e.code, 'code', 'INVALID_ARGUMENT'),
  );

  test('screenshot defaults and common inheritance include help/version and nested commands', () {
    final defaults = parser.parse(['screenshot']).options;
    expect(defaults.screenshotFormat, ScreenshotFormat.png);
    expect(defaults.screenshotQuality, 90);
    final flags = ['--screenshot-format', 'jpeg', '--screenshot-quality', '0'];
    for (final command in [
      ['screenshot'],
      ['snapshot'],
      ['logs'],
      ['connect', 'http://localhost:1/'],
      ['session', 'list'],
      ['session', 'show'],
      ['close'],
      ['tap', '@e1'],
      ['fill', '@e1', 'value'],
      ['swipe', '@e1', 'left'],
      ['scroll', '@e1', 'up'],
      ['wait', '--key', 'button'],
      ['workflow', 'schema'],
      ['workflow', 'validate', 'flow.json'],
      ['workflow', 'run', 'flow.json'],
      ['record', 'status'],
      ['record', 'stop'],
      [
        'record',
        'start',
        '/tmp/test.mp4',
        '--platform',
        'ios',
        '--device',
        'DEDBBEE8-F70D-4CF2-A150-930585F683B0',
      ],
      ['--help'],
      ['--version'],
    ]) {
      for (final args in [
        [...flags, ...command],
        [...command, ...flags],
      ]) {
        final options = parser.parse(args).options;
        expect(
          options.screenshotFormat,
          ScreenshotFormat.jpeg,
          reason: '$args',
        );
        expect(options.screenshotQuality, 0);
      }
    }
    expect(parser.usage, contains('--screenshot-format'));
    expect(parser.usage, contains('--screenshot-quality'));
    expect(parser.usage, contains('default 90'));
    expect(parser.usage, contains('white background'));
  });

  test('matching suffixes are retained, missing suffixes added; JPEG never inferred', () {
    for (final path in [
      'image.jpg',
      'image.jpeg',
      'image.JPG',
      'image.JPEG',
      'image',
    ]) {
      final value = parser.parse([
        'screenshot',
        path,
        '--screenshot-format=jpeg',
        '--screenshot-quality=100',
      ]);
      expect(value.params['path'], path == 'image' ? 'image.jpg' : path);
      expect(value.options.screenshotQuality, 100);
      expect(value.params.keys, [
        'path',
      ]); // Conversion policy stays in the CLI.
    }
    expect(parser.parse(['screenshot', 'image']).params['path'], 'image.png');
    expect(
      parser.parse(['screenshot', 'image.PNG']).params['path'],
      'image.PNG',
    );
    for (final args in [
      ['screenshot', 'image.jpg'],
      ['screenshot', 'image.jpeg'],
      ['screenshot', 'image.gif'],
      ['screenshot', 'image.png', '--screenshot-format=jpeg'],
      ['screenshot', 'image.webp', '--screenshot-format=jpeg'],
    ]) {
      expect(() => parser.parse(args), invalidArgument, reason: '$args');
    }
  });

  test('format and quality validation, duplicate/missing values recover JSON and session', () {
    final invalid = <List<String>>[
      ['screenshot', '--screenshot-format'],
      ['screenshot', '--screenshot-quality'],
      ['screenshot', '--screenshot-format=jpg'],
      ['screenshot', '--screenshot-format=JPEG'],
      ['screenshot', '--screenshot-format='],
      ['screenshot', '--screenshot-quality=90'],
      ['screenshot', '--screenshot-format=png', '--screenshot-quality=90'],
      ['--screenshot-format=jpeg', 'screenshot', '--screenshot-format=jpeg'],
      [
        '--screenshot-quality=90',
        'screenshot',
        '--screenshot-quality=90',
        '--screenshot-format=jpeg',
      ],
      for (final quality in [
        '-1',
        '101',
        '1.5',
        '+1',
        'NaN',
        '',
        '0x10',
        ' 1',
        '1 ',
        '99999999999999999999',
      ])
        [
          'screenshot',
          '--screenshot-format=jpeg',
          '--screenshot-quality=$quality',
        ],
    ];
    for (final args in invalid) {
      String? session;
      bool? json;
      expect(
        () => parser.parse(
          ['--session=issue13', '--json', ...args],
          onOutput: (s, j) {
            session = s;
            json = j;
          },
        ),
        invalidArgument,
        reason: '$args',
      );
      expect(session, 'issue13');
      expect(json, isTrue);
    }
  });

  test('option values and literal arguments do not become output flags', () {
    var json = true;
    expect(
      () => parser.parse([
        'screenshot',
        '--screenshot-format',
        '--json',
        '--unknown',
      ], onOutput: (_, j) => json = j),
      invalidArgument,
    );
    expect(json, isFalse);
    expect(
      parser.parse([
        'fill',
        '@e1',
        '--',
        '--screenshot-quality',
      ]).params['input'],
      '--screenshot-quality',
    );
  });
}
