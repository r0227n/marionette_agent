# marionette_agent_macos

Hidden Flutter application runner configuration and whole-display recording through ScreenCaptureKit SCStream/SCRecordingOutput (macOS 15+, full Xcode, Screen Recording permission).

Internal, unpublished member of the root Pub workspace. Resolve dependencies once
from the repository root. Target implementations depend on the platform interface;
the CLI selects implementations in `lib/src/platform/`.

See [architecture](../../docs/ARCHITECTURE.md#internal-platform-services) and the
[app integration guide](../../website/src/content/docs/en/getting-started/app-integration.md).


Still screenshots use a bundled standalone macOS XCTest runner and XCUIScreen. Full Xcode and macOS 13+ are required; allow --timeout 120000 for the initial build. The runner is locally ad-hoc signed and is cleaned up with its private build storage. More than two active displays support main-screen capture only because public XCTest APIs expose no display identity.
