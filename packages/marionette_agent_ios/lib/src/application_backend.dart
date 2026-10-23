import 'dart:io';

import 'package:marionette_agent_platform_interface/host_support.dart';

class IosApplicationBackend implements ApplicationBackend {
  const IosApplicationBackend({this.xcrun = 'xcrun'});
  final String xcrun;

  @override
  Future<void> start(ManagedApplication app, DateTime deadline) async {
    final o = app.options;
    final deviceSet = '${app.root.path}/devices';
    Future<String> simctl(List<String> args, DateTime limit) => app.command(
      xcrun,
      ['simctl', '--set', deviceSet, ...args],
      'iOS simulator',
      limit,
    );
    // Register cleanup before creating any device so partial startup is owned.
    app.cleanup = () async {
      if (app.device == null) return;
      final limit = DateTime.now().add(const Duration(seconds: 30));
      Future<void> cleanup(String action) async {
        final process = await OwnedProcess.start(
          xcrun,
          ['simctl', '--set', deviceSet, action, app.device!],
          label: 'iOS cleanup',
          deadline: limit,
        );
        await process.result(limit);
      }

      try {
        await cleanup('shutdown');
      } catch (_) {}
      await cleanup('delete');
    };
    await app.command(
      o.flutter,
      [
        'build',
        'ios',
        '--simulator',
        '--debug',
        '--no-pub',
        '--target',
        o.target,
      ],
      'iOS build',
      deadline,
    );
    final output = Directory('${o.project}/build/ios/iphonesimulator');
    final apps = await output
        .list()
        .where((f) => f is Directory && f.path.endsWith('.app'))
        .toList();
    if (apps.length != 1) {
      throw const PlatformException(
        'IO_ERROR',
        'Expected one built iOS simulator app',
      );
    }
    final bundle = await app.command(
      '/usr/libexec/PlistBuddy',
      ['-c', 'Print :CFBundleIdentifier', '${apps.single.path}/Info.plist'],
      'iOS bundle identity',
      deadline,
    );
    await Directory(deviceSet).create();
    app.device = await simctl([
      'create',
      'Marionette-Headless',
      o.deviceType!,
      o.runtime!,
    ], deadline);
    if (!RegExp(r'^[A-Fa-f0-9-]{36}$').hasMatch(app.device!)) {
      app.device = null;
      throw const PlatformException('IO_ERROR', 'Invalid simulator identity');
    }
    await simctl(['boot', app.device!], deadline);
    // bootstatus may fail on initial migration although the simulator can boot.
    // The actual install, VM connection and first observation prove readiness.
    try {
      await simctl(['bootstatus', app.device!, '-b'], deadline);
    } on PlatformException {
      remaining(deadline);
    }
    await simctl(['install', app.device!, apps.single.path], deadline);
    app.runner = await app.spawn(
      xcrun,
      [
        'simctl',
        '--set',
        deviceSet,
        'launch',
        '--console',
        app.device!,
        bundle,
        '--enable-dart-profiling',
        '--enable-checked-mode',
        '--verify-entry-points',
      ],
      'iOS application',
      deadline,
    );
    await app.waitUntil(() async {
      var text = app.runner!.output;
      if (!text.contains('Dart VM service is listening on')) {
        text = await simctl([
          'spawn',
          app.device!,
          'log',
          'show',
          '--last',
          '1m',
          '--style',
          'compact',
          '--predicate',
          'eventMessage CONTAINS "Dart VM service is listening"',
        ], deadline);
      }
      final matches = RegExp(
        r'Dart VM service is listening on (https?://[^\s]+)',
      ).allMatches(text);
      if (matches.isEmpty) return false;
      app.serviceUri = localServiceUri(matches.last[1]!);
      return app.serviceUri != null;
    }, deadline);
  }
}
