<div align="center">

# LATCH

### Your agent doesn't have an IP. Your laptop does. Latch onto it.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Shell](https://img.shields.io/badge/bash-4%2B-4EAA25?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![CDP](https://img.shields.io/badge/Chrome_DevTools_Protocol-1.3-4285F4?style=flat-square&logo=googlechrome)](https://chromedevtools.github.io/devtools-protocol/)

<sup>Give any datacenter-hosted agent a real, residential exit — by reaching for a device you already trust.</sup>

</div>

<br>

---

<br>

## The problem

Your agent runs on a VPS. A VPS has a datacenter IP. Every serious website WAF — Cloudflare,
DataDome, PerimeterX, and every marketplace with real users to protect (Khamsat, Mostaql, most
banks, most social platforms) — fingerprints that IP range and blocks it before your automation
even gets a cookie.

You can pay $50-300/month for a residential proxy pool. Or you can notice you already own a real
residential IP: **the laptop or phone sitting three feet from you, powered on, connected to the
internet, right now.**

Latch is the second option, built right.

```text
  agent (VPS, datacenter IP) ──403──> target site
  agent (VPS) ──SSH──> anchor (your laptop, residential IP) ──clean──> target site
```

## What it actually is

Three shell scripts and one architectural decision:

1. **`latch-start.sh`** — launches an isolated, headless Chromium/Brave instance on a remote
   "anchor" device (your laptop, a phone via Termux, any machine you can SSH into), with its
   `HeadlessChrome` User-Agent tell overridden and `AutomationControlled` blink feature disabled.
2. **`latch-tunnel.sh`** — opens a supervised SSH port-forward from the agent host to that
   browser's CDP port, so any CDP-speaking tool (Playwright, Puppeteer, a custom harness) on the
   agent host can drive it as if it were local.
3. **`latch-status.sh`** — a one-shot health check that tells you which layer broke (SSH down?
   tunnel dropped? browser fingerprint leaking Headless again?) instead of a bare timeout.

**The architectural decision that makes this safe:** Latch never touches your real, logged-in
browser profile. It copies-or-creates an isolated profile directory on the anchor device and
launches a *separate* browser process against it. Your actual session — the tabs you have open,
the things you're working on — is never touched, never focus-stolen, never at risk of a stray
automated click landing where you didn't expect it.

## Why not [residential proxy service]?

You can. It costs money every month, forever, for bandwidth you may use for an hour a week. Latch
costs the electricity your laptop was already drawing. The tradeoff is honest: a proxy service
gives you IP diversity across many exit points and doesn't require a device to stay awake; Latch
gives you one real, durable, trusted identity for free, tied to hardware you already trust more
than any proxy vendor's promise not to log your traffic.

Use both. Use Latch for the 90% of tasks where one stable identity is enough. Reach for a paid
residential pool only when you genuinely need IP rotation at scale.

## Why not [browser-relay style tools]?

Tools like `browser-relay` connect an agent to *your actual, currently-open* Chrome session —
cookies, tabs, login state, all of it. That's the right tool when the agent needs to act inside
an app you're already authenticated into. It is the wrong tool when the agent needs its own
long-lived identity that must never collide with what you're doing on your own screen right now.
Latch is deliberately the other shape: a second, isolated identity that happens to live on the
same trusted hardware — not a window into your real one.

## Quickstart

```bash
git clone https://github.com/kariemSeiam/latch.git && cd latch

# 1. Launch an isolated headless browser on your anchor device
./bin/latch-start.sh you@your-laptop-tailscale-ip

# 2. Tunnel it to wherever your agent/automation actually runs
./bin/latch-tunnel.sh you@your-laptop-tailscale-ip

# 3. Verify both layers are healthy
./bin/latch-status.sh you@your-laptop-tailscale-ip
```

Point any CDP client at `http://127.0.0.1:9333` and drive the browser normally. If you're using
Hermes/Claude-family agent tooling with `browser_exec`:

```bash
hermes config set browser.cdp_url "http://127.0.0.1:9333"
```

## Android anchors

Any rooted Android device reachable over SSH (Termux + Magisk — the same setup Tailscale-based
personal-device toolkits already assume) works as an anchor too, no separate command needed:
`latch-start.sh`/`latch doctor`/`latch stop` auto-detect Android via `getprop` on the remote host
and route to Android-specific logic automatically.

```bash
./bin/latch-doctor.sh you@your-phone-tailscale-ip   # flags root/Chrome/python3 gaps explicitly
./bin/latch-start.sh  you@your-phone-tailscale-ip   # detects Android, routes to the Android path
./bin/latch-tunnel.sh you@your-phone-tailscale-ip   # identical to the desktop path — no changes
```

**Why Android needed real new code, not just a different binary path:** Android Chrome never
opens a real TCP port for `--remote-debugging-port`, even with the flag set — confirmed live
against a real device (Pixel 3a XL, Chrome 153): the only thing that ever appears is a Linux
*abstract* unix socket, `chrome_devtools_remote` (the same target `adb forward` uses over USB).
SSH's `-L` can forward a TCP port to another TCP port; it has no notion of an abstract unix
socket at all. `bin/latch-android-bridge.py` closes that gap: a small stdlib-only daemon that
runs on the anchor and relays local TCP connections into the abstract socket, so the rest of the
pipeline (`latch-tunnel.sh`, `latch-status.sh`, `latch-stop.sh`) works completely unmodified once
it's running. See `docs/ARCHITECTURE.md` for the full bridge design and the fingerprint
implications (a real mobile Chrome UA is actually a *better* anti-detection story than desktop
headless, not a compromise).

Requirements beyond the desktop path: root (`su -c` — the bridge itself needs no elevated
privilege, but flipping Chrome's DevTools flag and force-stopping/relaunching it does), Chrome
installed, and Termux's bundled `python3` (present by default on any standard Termux install).
`latch doctor` checks all three explicitly and names exactly which one is missing.

## Requirements

- An "anchor" device with a real residential/mobile IP, an installed Chromium-family browser, and
  SSH reachable from the agent host (a Tailscale tailnet is the easiest way to get this without
  exposing SSH publicly — any reachable SSH host works).
- The agent host needs `ssh` and `curl`. No language runtime, no dependencies, no daemon to
  install on either side.

## What Latch does NOT solve

- **The anchor device must be awake and network-reachable.** This is a physical constraint, not a
  bug — Latch trades "always-on cloud infrastructure" for "zero recurring cost," and that trade
  has a real cost of its own. If you need 24/7 uptime independent of any physical device, pair
  Latch with a small always-on anchor (a cheap always-on mini-PC, a phone left plugged in) rather
  than a laptop that sleeps.
- **CAPTCHAs and behavioral fingerprinting beyond IP + UA.** Latch fixes the two most common,
  most brutal blockers (datacenter IP range, `HeadlessChrome` UA string). It does not solve
  canvas/WebGL fingerprinting or mouse-movement heuristics — for targets that go that far, you
  need a dedicated stealth-browser project layered on top.
- **Multi-anchor load balancing / IP rotation.** Latch is one identity, deliberately. If you need
  rotation across many residential exits, that's a different tool (or several Latch anchors
  scripted in parallel — nothing stops you, it's just not what v1 automates).

## Origin

Built the hard way first: khamsat.com and mostaql.com (major Arabic freelance marketplaces) both
return a hard `403 Forbidden` to any headless-Chromium request from a datacenter IP — confirmed
even after spoofing every header, including a same-datacenter headless launch with a fully
rewritten User-Agent. The fix that actually worked was routing through a real laptop's residential
connection. Latch is that fix, generalized and rebuilt clean, so the next site that blocks a VPS
doesn't cost another afternoon of trial and error.

## License

MIT. Use it, fork it, ship it.
