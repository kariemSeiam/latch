# Architecture

```text
┌─────────────────────────┐        SSH (key-based, or Tailscale)        ┌──────────────────────────┐
│   agent host (VPS)      │ ───────────────────────────────────────────▶│  anchor device (laptop,  │
│                          │                                              │  phone, any residential  │
│  latch-tunnel.sh         │◀──── ssh -N -L <port>:127.0.0.1:<port> ────│  or trusted network)     │
│  local:9333 ────────────┼──────────────────────────────────────────────┼─▶ chrome --headless=new  │
│                          │                                              │    --remote-debugging-   │
│  your CDP client         │                                              │    port=9333             │
│  (Playwright/Puppeteer/  │                                              │    --user-data-dir=      │
│   browser_exec/custom)   │                                              │    /tmp/latch-profile    │
└─────────────────────────┘                                              └──────────────────────────┘
```

## Why an SSH tunnel and not a direct CDP exposure

Chrome's remote-debugging port is unauthenticated by design — anything that can reach
it can execute arbitrary JS in the browser context. Binding it to `127.0.0.1` on the
anchor and reaching it only through an SSH tunnel (itself authenticated by SSH keys)
means the CDP port is never actually exposed to the network, on either end. This is
the same reasoning Tailscale's own docs give for tunneling debug ports rather than
opening them — Latch just applies it to CDP specifically.

## Why an isolated profile directory, not the anchor's real browser profile

Two independent, both discovered the hard way:

1. **`SingletonLock` collisions.** Chrome refuses to start a second instance against a
   profile directory another running instance already holds a lock on. Pointing
   `--user-data-dir` at someone's live, logged-in profile means Latch either fails to
   launch (lock held) or, worse, the real browser is what fails to launch next time the
   human opens it.
2. **Blast radius.** An agent executing JS in a page context via CDP can, in principle,
   read cookies, localStorage, and open tabs. Against an isolated profile, the blast
   radius of any bug in the calling agent is "an empty browser profile." Against a real
   profile, it's every website that human is logged into.

The isolated profile can still be seeded with real cookies/logins if you explicitly
copy them in (`cp -r <real-profile> <latch-profile>` before `latch-start.sh`) — that's
a deliberate choice you make per use case, not the default behavior.

**This section describes the desktop path only.** Android has no equivalent concept of
a swappable `--user-data-dir` per launch that isn't itself Chrome's one real app-data
profile — see the Android bridge section below for what isolation means there instead.

## Android: no TCP CDP port, only an abstract unix socket

Everything above this section assumes a desktop-shaped Chrome: a real TCP listening
socket for `--remote-debugging-port`, a swappable `--user-data-dir`, and a `--headless`
mode. Android Chrome has none of these, confirmed live against a real device (Pixel 3a
XL, LineageOS 22.2, Chrome 153):

- `--remote-debugging-port=<N>` is silently ignored as a TCP bind request. The *only*
  thing that ever appears is a Linux **abstract** unix socket named
  `chrome_devtools_remote` — visible via `cat /proc/net/unix | grep devtools` as a line
  starting with `@chrome_devtools_remote` (the `@` is what marks it abstract rather than
  a real filesystem path). This is the exact same target `adb forward tcp:PORT
  localabstract:chrome_devtools_remote` connects to over USB — Latch's Android bridge is
  the SSH-reachable equivalent of that same mechanism, no USB cable involved.
- SSH's `-L`/`-R` port forwarding only understands TCP endpoints on both ends. It has no
  concept of a unix socket, abstract or otherwise, so `latch-tunnel.sh`'s normal
  `ssh -L <port>:127.0.0.1:<port>` has nothing to connect to on the remote side without
  something first exposing that abstract socket as a real TCP port.
- `bin/latch-android-bridge.py` is that something: a small stdlib-only Python daemon
  (Termux's bundled `python3`, no pip install needed) that binds a local TCP port and
  relays every connection 1:1 into the abstract socket via `AF_UNIX` with a
  NUL-prefixed name (`socket.connect("\0chrome_devtools_remote")` — the NUL prefix is
  what makes a Linux unix-socket name abstract instead of a filesystem path). Once this
  bridge is running, `latch-tunnel.sh`, `latch-status.sh`, and `latch-stop.sh` all work
  completely unmodified — from their point of view it's just a TCP port that happens to
  answer CDP requests, identical to the desktop case.
- **No `--headless` mode exists on Android at all** — it is always a real mobile browser
  UI. This is not a limitation Latch works around; it is a *better* starting fingerprint
  than desktop headless. Verified live: `/json/version` through the bridge returned a
  stock `Mozilla/5.0 (Linux; Android 10; K) ... Mobile Safari/537.36` User-Agent with
  zero overrides needed — there was never a `HeadlessChrome` string to hide in the first
  place, because the browser genuinely isn't headless. What `latch-start.sh` does with
  an explicit `--user-agent` flag on desktop, Android gets for free by being a real
  phone.
- **Isolation is achieved differently, not skipped.** Desktop Latch isolates via a
  separate `--user-data-dir`; Android Chrome has one real profile per app install with
  no equivalent flag to redirect it elsewhere. `latch-start-android.sh` instead
  force-stops Chrome before flipping its DevTools-enabling command-line flags file
  (`/data/local/tmp/chrome-command-line`) and relaunching — the blast-radius argument
  from the desktop section above still applies to *what the agent can reach through
  CDP*, but on Android that surface is the device owner's one real Chrome profile, not
  a disposable one. Treat an Android anchor's Chrome exactly as carefully as you would
  the desktop anchor's *real* (non-isolated) profile — see the "browser-relay style
  tools" caveat in the README for when that's the wrong tool for the job.
- Root (`su -c`) is required for exactly two things: writing the command-line flags
  file to `/data/local/tmp` (a root-owned path) and force-stopping/relaunching Chrome
  via `am`. The bridge process itself, once running, needs no elevated privilege beyond
  a normal unix-socket connect.

## Why the User-Agent override matters

`chrome --headless=new` still self-reports as `HeadlessChrome/<version>` in its own
`navigator.userAgent` and in the CDP `/json/version` endpoint, even though `headless=new`
mode is otherwise nearly indistinguishable from a normal window at the rendering level.
Every WAF vendor with a bot-detection product checks this string first — it is the
cheapest, highest-signal tell available to them, cheaper than canvas fingerprinting or
behavioral analysis. Overriding `--user-agent` to a normal desktop Chrome string removes
this specific tell. It does **not** remove `navigator.webdriver` or other automation
markers on its own — `--disable-blink-features=AutomationControlled` handles the former;
deeper fingerprinting (canvas, WebGL, font enumeration) is out of scope for Latch by
design (see README's "What Latch does NOT solve").

## Failure modes and how each script maps to one

| Failure mode | Symptom | Script that catches/fixes it |
|---|---|---|
| Anchor asleep / unreachable | `ssh` times out | `latch-doctor.sh` (preflight), `latch-status.sh` (runtime) |
| Stale profile lock from a crashed previous run | Chrome exits immediately, CDP port never opens | `latch-start.sh` (`pkill -9 -f user-data-dir=...` before every launch) |
| `HeadlessChrome` UA leaking through | Target site 403s despite a "working" tunnel | `latch-status.sh` greps `/json/version` for the string and flags it explicitly |
| No browser binary on a new/unfamiliar anchor | `latch-start.sh` can't find anything to launch | `latch-doctor.sh` runs the same binary search first, so you find out before wasting a launch attempt |
| Tunnel silently dies mid-session (network blip) | Agent's CDP calls start timing out with no clear error | `latch-status.sh` — run it as a health check before trusting a long-idle tunnel; `ServerAliveInterval=30` in `latch-tunnel.sh` reduces how often this happens |
| Android anchor has no root | `latch-start-android.sh` fails writing the flags file / force-stopping Chrome | `latch-doctor.sh`'s Android branch checks `su -c 'id -u'` explicitly before any launch is attempted |
| Android anchor lacks Termux's python3 | Bridge fails to launch, `/json/version` never responds through the local port | `latch-doctor.sh`'s Android branch checks for the interpreter at its known path directly |
| Stale bridge process holding the Android CDP port | New `latch-start-android.sh` run can't bind, or old traffic mixes with new | `latch-start-android.sh` `pkill -f latch_android_bridge.py` before every launch, same discipline as the desktop stale-lock fix |
