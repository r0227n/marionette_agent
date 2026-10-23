/// CLI composition of platform contracts, launchers, and recording lifecycle.
library;

export 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
export 'package:marionette_agent_platform_interface/host_support.dart'
    show terminationRequests;
export 'package:marionette_agent_flutter/marionette_agent_flutter.dart'
    show PngScreenRecorder;

export 'recording/recording_manager.dart';
export 'devices.dart';
export 'application/application_launcher.dart';
