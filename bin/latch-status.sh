#!/usr/bin/env bash
# latch-status.sh — health check for a running latch (anchor browser +
# local tunnel). Exits 0 and prints OK when both layers are confirmed live;
# exits non-zero with a diagnostic otherwise.
#
# Usage: ./latch-status.sh <anchor_ssh_host> [cdp_port] [local_port]
set -euo pipefail

ANCHOR="${1:?usage: latch-status.sh <ssh_host> [cdp_port] [local_port]}"
CDP_PORT="${2:-9333}"
LOCAL_PORT="${3:-$CDP_PORT}"

FAIL=0

echo "[latch] checking local tunnel (127.0.0.1:${LOCAL_PORT})..."
VER=$(curl -s --max-time 5 "http://127.0.0.1:${LOCAL_PORT}/json/version" || true)
if echo "$VER" | grep -q webSocketDebuggerUrl; then
  echo "  tunnel: OK"
  if echo "$VER" | grep -qi '"User-Agent":"[^"]*Headless'; then
    echo "  browser UA: WARNING — still advertises HeadlessChrome (will get bot-blocked)"
    FAIL=1
  else
    echo "  browser UA: OK (clean, non-headless string)"
  fi
else
  echo "  tunnel: DOWN — no response on local:${LOCAL_PORT}"
  FAIL=1
fi

echo "[latch] checking anchor reachability (${ANCHOR})..."
if ssh -o ConnectTimeout=8 "$ANCHOR" 'echo alive' 2>/dev/null | grep -q alive; then
  echo "  ssh: OK"
else
  echo "  ssh: DOWN — anchor unreachable (asleep, network drop, or Tailscale down)"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "[latch] STATUS: OK — ready for browser automation"
else
  echo "[latch] STATUS: DEGRADED — run latch-start.sh and latch-tunnel.sh again" >&2
fi
exit "$FAIL"
