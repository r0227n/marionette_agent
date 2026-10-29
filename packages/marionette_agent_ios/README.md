# marionette_agent_ios

iOS Simulator inventory, private device-set application launch/cleanup, and XCUIScreen screenshots and timestamped recordings on macOS.

Internal, unpublished member of the root Pub workspace. Resolve dependencies once
from the repository root. Target implementations depend on the platform interface;
the CLI selects implementations in `lib/src/platform/`.

See [architecture](../../docs/ARCHITECTURE.md#internal-platform-services) and the
[app integration guide](../../website/src/content/docs/en/getting-started/app-integration.md).

XCUIScreen screenshots require a booted iOS Simulator UDID in the default device set. The bundled standalone XCTest runner is built on first use and reused within the daemon; allow a longer timeout. It returns PNG bytes and provenance to the shared artifact writer; physical devices are unsupported. See the [capture contract](../../docs/SPEC.md#native-ios-screenshots).
