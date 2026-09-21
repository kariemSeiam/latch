#!/usr/bin/env bash
# latch-stop.sh — cleanly tear down a latch: kill the local tunnel process
# and the anchor's isolated browser process. Leaves the anchor device and
# its real, non-latch browser sessions untouched.
#
# Usage: ./latch-stop.sh <anchor_ssh_host> [profile_dir] [local_port]
set -euo pipefail

ANCHOR="${1:?usage: latch-stop.sh <ssh_host> [profile_dir] [local_port]}"
PROFILE_DIR="${2:-/tmp/latch-profile}"
LOCAL_PORT="${3:-9333}"

echo "[latch] stopping local tunnel on 127.0.0.1:${LOCAL_PORT}..."
if pkill -f "${LOCAL_PORT}:127.0.0.1:" 2>/dev/null; then
  echo "  killed local ssh -L tunnel process(es)"
else
  echo "  no local tunnel process found (already stopped)"
fi

if ssh -o ConnectTimeout=8 -o BatchMode=yes "$ANCHOR" 'command -v getprop' >/dev/null 2>&1; then
  echo "[latch] stopping Android anchor's Chrome + CDP bridge (${ANCHOR})..."
  CHROME_PKG="${LATCH_ANDROID_CHROME_PKG:-com.android.chrome}"
  # PROFILE_DIR is unused on the Android path (no isolated profile dir —
  # the bridge/flags-file approach instead, see latch-start-android.sh);
  # kept as an accepted-but-ignored arg so the CLI's stop signature stays
  # identical across both platforms.
  if ssh "$ANCHOR" "su -c 'pkill -f latch_android_bridge.py; am force-stop ${CHROME_PKG}; rm -f /data/local/tmp/chrome-command-line'" 2>/dev/null; then
    echo "  killed anchor bridge + Chrome, removed the DevTools flags file"
  else
    echo "  no matching anchor process found (already stopped)"
  fi
  echo "[latch] stopped. Your anchor device's normal browser sessions were not touched."
  exit 0
fi

echo "[latch] stopping isolated browser on ${ANCHOR} (profile: ${PROFILE_DIR})..."
# PROFILE_DIR expands client-side intentionally (shellcheck SC2029) — it is
# agent-host config identifying which anchor-side profile to target.
if ssh "$ANCHOR" "pkill -9 -f 'user-data-dir=${PROFILE_DIR}'" 2>/dev/null; then
  echo "  killed anchor browser process(es)"
else
  echo "  no matching anchor browser process found (already stopped)"
fi

echo "[latch] stopped. Your anchor device's normal browser sessions were not touched."
