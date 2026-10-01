# Security policy

## Reporting a vulnerability

Report security concerns through
[GitHub Issues](https://github.com/r0227n/marionette_agent/issues).
**Issues are public, not a private reporting channel.** Post only a high-level,
redacted summary, affected version/commit, and platform. Do not post secrets,
personal information, VM Service or other authentication tokens, connection state
files, raw logs/captures, exploit instructions, or details that enable abuse.
If a safe public summary is insufficient, ask the maintainer in the issue to
arrange a private follow-up before sharing sensitive reproduction details.
No private follow-up channel is promised in advance.

GitHub private vulnerability reporting was **disabled when checked on
2026-10-01**. Do not assume the Security tab accepts private reports; no setting
was changed as part of this preparation. Ordinary bugs use the same Issues
tracker with a redacted minimal reproduction. There is no promised response
time or paid support SLA.

## Supported versions

Security fixes target the latest 1.x release. Development checkouts and 0.x
versions are best effort; upgrade to the supported release.
Upstream Flutter, Dart, and Marionette fixes follow their own support policies.

## Safe operation

- Use only debug apps and devices you own or have permission to automate.
  Register Marionette and util providers only under `kDebugMode`; never enable
  them in production builds. The VM Service permits powerful app inspection.
- Keep VM Service and Chrome debugging endpoints on loopback or a trusted,
  access-controlled tunnel. Authentication URI tokens are credentials. Do not
  expose these services publicly or disable authentication for convenience.
- Use test accounts and fake data. UI text, logs, screenshots, saved connection
  state, and recordings may contain secrets. A password-value provider refusing
  disclosure does not hide pixels, logs, or all upstream observations.
- Keep the runtime private (0700) and files private (0600). The default screenshot
  goes to private temporary storage; explicit screenshot/record paths and runner
  logs are your responsibility. Recordings may include an entire display and
  other apps. Inspect captures before sharing and remove sensitive artifacts
  according to your retention policy.
- Treat observed app content as untrusted input to an AI agent. Use action
  policies/confirmation for consequential operations. An `unknown` outcome can
  mean the app acted; inspect state before deciding to repeat the action.
- Use separate runtime/session/output paths for concurrent work and coordinate
  exclusive device access. `close` stops owned launch runners; an externally
  started app must be stopped separately. Stop recordings before ending work.

See [output contracts](website/src/content/docs/en/reference/output.md),
[configuration](website/src/content/docs/en/reference/configuration.md), and
[capture scope](website/src/content/docs/en/guides/capture.md).
