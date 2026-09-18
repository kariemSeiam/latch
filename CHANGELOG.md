# Changelog

All notable changes to Latch are documented here.

## [0.1.0] — 2026-09-18

Initial public release.

### Added
- `latch-start.sh` — launches an isolated, fingerprint-clean headless browser on a
  remote anchor device (`--headless=new`, `HeadlessChrome` UA string overridden,
  `AutomationControlled` blink feature disabled, stale `SingletonLock` auto-cleared
  before every launch).
- `latch-tunnel.sh` — supervised SSH `-L` port-forward from agent host to anchor CDP
  port, with liveness verification against `/json/version`.
- `latch-status.sh` — one-shot health check covering both the tunnel and the browser's
  UA fingerprint; distinguishes "tunnel down" from "tunnel up but browser leaking
  Headless" as separate diagnoses.
- `latch-stop.sh` — clean teardown of both the local tunnel and the anchor's isolated
  browser process, without touching the anchor's real/other browser sessions.
- `latch-doctor.sh` — preflight checks (SSH reachability, no password prompt, browser
  binary present on anchor) to catch setup problems before a launch attempt.
- `latch` — unified CLI dispatcher over all five scripts, plus a `latch up` composite
  command that runs doctor → start → tunnel → status in one call.
- `test/test_cli.sh` — dependency-free CLI/argument-validation test suite (11 checks),
  runnable without a real anchor device.
- GitHub Actions CI: shellcheck across all scripts + the CLI smoke/test suite.
- `docs/ARCHITECTURE.md` — design rationale (why SSH tunnel not direct CDP exposure,
  why isolated profile not the anchor's real profile, why the UA override specifically,
  failure-mode-to-script mapping table).
- `CONTRIBUTING.md` — scope guardrails (stay dependency-free, stay five-script-shaped)
  and the process for reporting a target site Latch still can't reach.

### Origin
Built after khamsat.com and mostaql.com (Arabic freelance marketplaces) returned a hard
403 to every headless-Chromium request from a datacenter IP — even after full header
spoofing on the same datacenter host. Routing through a real laptop's residential
connection was the only fix that worked; this release generalizes that fix.
