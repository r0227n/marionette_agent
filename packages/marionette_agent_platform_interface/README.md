# marionette_agent_platform_interface

Shared launch/recording contracts, platform errors, and target identity. `host_support.dart` provides reusable process ownership, deadlines, inventory subprocesses, and application cleanup. It selects no target implementation.

Internal, unpublished member of the root Pub workspace. Resolve dependencies once
from the repository root. Target implementations depend on the platform interface;
the CLI selects implementations in `lib/src/platform/`.

See [architecture](../../docs/ARCHITECTURE.md#internal-platform-services) and the
[app integration guide](../../website/src/content/docs/en/getting-started/app-integration.md).
