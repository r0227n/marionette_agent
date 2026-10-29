/// CLI composition of platform contracts, launchers, and recording lifecycle.
library;

export 'package:marionette_agent_platform_interface/marionette_agent_platform_interface.dart';
export 'package:marionette_agent_platform_interface/host_support.dart'
    show terminationRequests;
export 'package:marionette_agent_video/marionette_agent_video.dart'
    show PngScreenRecorder, FfmpegKitVideoEncoder;

export 'recording/recording_manager.dart';
export 'devices.dart';
export 'application/application_launcher.dart';
