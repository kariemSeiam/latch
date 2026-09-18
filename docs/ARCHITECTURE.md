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
