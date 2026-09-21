---
title: Prepare your Flutter app
description: Initialize the Marionette binding in debug mode and give your app stable interaction targets.
---

Enable the Marionette binding in your app so the CLI can observe and operate it through the VM Service. Start with an entrypoint that enables it only in debug mode.

## Initialize the binding

Add the dependency from your app directory.

```sh
flutter pub add marionette_flutter:0.6.0
```

Initialize the binding before `runApp`. Replace `MyApp` with your existing root widget.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const MyApp());
}
```

Initialize Marionette first if other startup code also needs a binding. Run the app in debug mode, then `connect` using that run’s VM Service URI.

## Add stable keys

Give widgets used by your procedures unique keys. This reduces the procedure’s dependence on UI wording and translations.

```dart
TextField(key: const ValueKey('email'))
```

```sh
marionette-agent snapshot
marionette-agent fill --key email 'reader@example.com'
marionette-agent snapshot
```

An operation is rejected if multiple observed targets share a key. Keep each target unique within the screen you operate on.

## Enable additional providers

Register the Flutter extensions from `marionette_agent_util` for `get value`, `is checked`, and additional input operations. This is currently a local package in this repository. Add a path dependency pointing to `packages/marionette_agent_util` in your checkout, then register it after the binding is initialized.

```dart
import 'package:marionette_agent_util/flutter.dart';

// After MarionetteBinding.ensureInitialized(), in the debug branch:
registerAgentExtensions();
```

The example already registers it. Annotated screenshots require a separate mapped screenshot provider that maps element bounds to the captured image.

See the [example initialization](https://github.com/r0227n/marionette_agent/blob/develop/example/lib/main.dart) and [helper package](https://github.com/r0227n/marionette_agent/tree/develop/packages/marionette_agent_util) for implementations. A missing capability may return `UNSUPPORTED_CAPABILITY`; an unobserved value is distinct from an empty string or false.
