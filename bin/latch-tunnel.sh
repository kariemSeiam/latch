#!/usr/bin/env bash
# latch-tunnel.sh — open (and supervise) a persistent SSH tunnel from this
# agent host to the CDP port on a latch anchor device, and point the local
# browser-automation toolchain at it.
#
# Usage: ./latch-tunnel.sh <anchor_ssh_host> [cdp_port] [local_port]
set -euo pipefail

ANCHOR="${1:?usage: latch-tunnel.sh <ssh_host> [cdp_port] [local_port]}"
CDP_PORT="${2:-9333}"
LOCAL_PORT="${3:-$CDP_PORT}"

echo "[latch] killing any stale tunnel on local:${LOCAL_PORT}..."
pkill -f "${LOCAL_PORT}:127.0.0.1:${CDP_PORT}" 2>/dev/null || true
sleep 1

echo "[latch] opening tunnel: local ${LOCAL_PORT} -> ${ANCHOR}:${CDP_PORT}"
# NOTE: run this line via your orchestrator's own background-process
# mechanism (e.g. Hermes terminal(background=true)) rather than a bare `&`
# if you want the caller to track/kill it later. This script documents the
# exact command; it does not itself daemonize when run standalone.
nohup ssh -N -L "${LOCAL_PORT}:127.0.0.1:${CDP_PORT}" \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  "$ANCHOR" > /tmp/latch-tunnel.log 2>&1 &
TUNNEL_PID=$!
echo "[latch] tunnel pid: ${TUNNEL_PID}"

sleep 2
if curl -s "http://127.0.0.1:${LOCAL_PORT}/json/version" | grep -q webSocketDebuggerUrl; then
  echo "[latch] tunnel verified: http://127.0.0.1:${LOCAL_PORT}/json/version responds"
else
  echo "[latch] ERROR: tunnel did not come up cleanly, check /tmp/latch-tunnel.log" >&2
  exit 1
fi

echo "[latch] point your browser tool at it, e.g.:"
echo "  hermes config set browser.cdp_url \"http://127.0.0.1:${LOCAL_PORT}\""
