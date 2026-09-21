# Changelog

All notable changes to Latch are documented here.

## [Unreleased]

### Added
- **Android anchor support.** Any rooted Android device reachable over SSH (Termux +
  Magisk) now works as a Latch anchor, auto-detected via `getprop` — no new top-level
  command needed, `latch-start.sh`/`latch doctor`/`latch stop` route to Android-specific
  logic transparently.
- `bin/latch-android-bridge.py` — a stdlib-only Python TCP<->abstract-unix-socket relay,
  the missing piece that makes Android's `chrome_devtools_remote` abstract socket
  reachable over a plain SSH `-L` tunnel (SSH forwarding only understands TCP; Android
  Chrome never opens a real TCP CDP port, confirmed live against a real device).
- `bin/latch-start-android.sh` — the Android equivalent of `latch-start.sh`: flips
  Chrome's DevTools command-line flag, pushes and launches the bridge, verifies
  `/json/version` responds before returning.
- `latch-doctor.sh` and `latch-stop.sh` both gained an Android branch (root check,
  Chrome-installed check, Termux python3 check for doctor; bridge+Chrome teardown via
  `su -c` for stop) so the existing five-verb CLI shape didn't need to grow a sixth verb.
- README "Android anchors" section and `docs/ARCHITECTURE.md` "Android: no TCP CDP port"
  section documenting why this needed real new code (no TCP port, no `--headless` mode,
  no swappable `--user-data-dir`) rather than a config flag on the existing scripts.

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
