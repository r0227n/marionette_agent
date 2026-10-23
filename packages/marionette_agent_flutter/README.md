# marionette_agent_flutter

Flutter tester launch and PNG-to-video recording through `ffmpeg_kit_extended_flutter: 1.0.0` native assets. The pinned generated C ABI is isolated in `ffmpeg_kit_encoder.dart` so the host library works without a Flutter engine. The workspace hook selects video/LGPL/small; no PATH ffmpeg executable is invoked. `flutter.dart` separately exports debug providers and hidden-frame rendering for Flutter apps; the host library does not import the Flutter engine.

Internal, unpublished member of the root Pub workspace. Resolve dependencies once
from the repository root. Target implementations depend on the platform interface;
the CLI selects implementations in `lib/src/platform/`.

See [architecture](../../docs/ARCHITECTURE.md#internal-platform-services) and the
[app integration guide](../../website/src/content/docs/en/getting-started/app-integration.md).
