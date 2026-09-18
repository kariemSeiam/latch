#!/usr/bin/env bash
# latch-start.sh — launch an isolated, anti-detection headless browser on a
# remote personal device (the "anchor"), reachable over SSH+CDP from an agent
# host that has no clean egress IP of its own.
#
# Usage: ./latch-start.sh <anchor_ssh_host> [remote_profile_dir] [cdp_port]
#
# Requires: an existing Chrome/Chromium/Brave install on the anchor, and a
# working `ssh <anchor_ssh_host>` (key-based, no password prompt).
set -euo pipefail

ANCHOR="${1:?usage: latch-start.sh <ssh_host> [profile_dir] [cdp_port]}"
PROFILE_DIR="${2:-/tmp/latch-profile}"
CDP_PORT="${3:-9333}"
BROWSER_BIN="${LATCH_BROWSER_BIN:-}"

echo "[latch] resolving a browser binary on ${ANCHOR}..."
if [ -z "$BROWSER_BIN" ]; then
  BROWSER_BIN=$(ssh "$ANCHOR" '
    for b in google-chrome google-chrome-stable chromium chromium-browser \
             /opt/brave.com/brave-origin-nightly/brave \
             /opt/brave.com/brave/brave brave-browser; do
      p=$(command -v "$b" 2>/dev/null || true)
      if [ -n "$p" ]; then echo "$p"; break; fi
      if [ -x "$b" ]; then echo "$b"; break; fi
    done
  ')
fi
if [ -z "$BROWSER_BIN" ]; then
  echo "[latch] ERROR: no browser binary found on ${ANCHOR}. Set LATCH_BROWSER_BIN explicitly." >&2
  exit 1
fi
echo "[latch] using: ${BROWSER_BIN}"

# Isolate: never reuse the anchor's live/active profile directory (that
# collides with SingletonLock and risks disturbing a real session in front
# of the device's owner). Seed the isolated profile from a real profile ONLY
# if explicitly asked — otherwise start clean.
ssh "$ANCHOR" bash -s -- "$PROFILE_DIR" "$CDP_PORT" "$BROWSER_BIN" <<'REMOTE'
set -euo pipefail
PROFILE_DIR="$1"; CDP_PORT="$2"; BROWSER_BIN="$3"

pkill -9 -f "user-data-dir=${PROFILE_DIR}" 2>/dev/null || true
sleep 1
mkdir -p "$PROFILE_DIR"

LAUNCH_SCRIPT="/tmp/$(basename "$PROFILE_DIR")-launch.sh"
cat > "$LAUNCH_SCRIPT" <<EOF
#!/bin/bash
pkill -f "user-data-dir=${PROFILE_DIR}" 2>/dev/null || true
sleep 1
exec "${BROWSER_BIN}" \\
  --user-data-dir="${PROFILE_DIR}" \\
  --remote-debugging-port=${CDP_PORT} --remote-debugging-address=127.0.0.1 \\
  --no-first-run --no-default-browser-check --headless=new \\
  --no-sandbox --disable-dev-shm-usage \\
  --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36" \\
  --disable-blink-features=AutomationControlled \\
  about:blank
EOF
chmod +x "$LAUNCH_SCRIPT"

nohup bash -c "nohup '$LAUNCH_SCRIPT' > /tmp/$(basename "$PROFILE_DIR").log 2>&1 < /dev/null & disown; sleep 1; echo started"
REMOTE

echo "[latch] waiting for CDP on ${ANCHOR}:${CDP_PORT}..."
for i in $(seq 1 10); do
  sleep 1
  UA=$(ssh "$ANCHOR" "curl -s http://127.0.0.1:${CDP_PORT}/json/version" 2>/dev/null | grep -o '"User-Agent":[^,]*' || true)
  if [ -n "$UA" ]; then
    echo "[latch] browser is up: ${UA}"
    if echo "$UA" | grep -qi headless; then
      echo "[latch] WARNING: User-Agent still says Headless — a stale process may be holding the port." >&2
      echo "[latch] retrying a hard kill + relaunch once..." >&2
      ssh "$ANCHOR" "pkill -9 -f 'user-data-dir=${PROFILE_DIR}'" || true
      sleep 2
      ssh "$ANCHOR" "nohup bash -c \"nohup '/tmp/$(basename "$PROFILE_DIR")-launch.sh' > /tmp/$(basename "$PROFILE_DIR").log 2>&1 < /dev/null & disown\""
      sleep 3
    else
      break
    fi
  fi
done

echo "[latch] launched. Next: latch-tunnel.sh ${ANCHOR} ${CDP_PORT}"
