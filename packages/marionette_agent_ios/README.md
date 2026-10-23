# marionette_agent_ios

iOS Simulator inventory, private device-set application launch/cleanup, native screenshots, and simctl screen recording on macOS.

Internal, unpublished member of the root Pub workspace. Resolve dependencies once
from the repository root. Target implementations depend on the platform interface;
the CLI selects implementations in `lib/src/platform/`.

See [architecture](../../docs/ARCHITECTURE.md#internal-platform-services) and the
[app integration guide](../../website/src/content/docs/en/getting-started/app-integration.md).

Native screenshots require a booted iOS Simulator UDID in the default device set. They return PNG bytes and provenance to the shared artifact writer; physical devices are unsupported. See the [capture contract](../../docs/SPEC.md#native-ios-screenshots).
