/// Internal platform services for marionette_agent. Platform commands and
/// native dependencies belong here, not in the CLI package.
library;

export 'src/recording/recorder.dart';
export 'src/recording/png_recorder.dart';
export 'src/recording/recording_manager.dart';

export 'src/platform_exception.dart';
export 'src/lifecycle/termination_signals.dart';

export 'src/devices.dart';

export 'src/application/application_launcher.dart';
