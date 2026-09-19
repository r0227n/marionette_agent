/// Result scope is the same for syntax errors, local commands and IPC delivery.
bool usesSession(String? command, {Object? action, bool all = false}) =>
    switch (command) {
      'help' ||
      'version' ||
      'skills' ||
      'doctor' ||
      'device' ||
      'install' ||
      'upgrade' => false,
      'workflow' => action == 'run',
      'session' => action != 'list',
      'close' => !all,
      _ => true,
    };
