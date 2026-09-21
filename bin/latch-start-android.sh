#!/usr/bin/env bash
# latch-start-android.sh — launch Chrome + a CDP TCP bridge on a rooted
# Android anchor (Termux + Magisk), reached over the same SSH/Tailscale link
# any other Latch anchor uses.
#
# Why this is a separate script and not a branch inside latch-start.sh:
# Android Chrome never opens a real TCP listening socket for
# --remote-debugging-port — verified live against a real device (Pixel 3a
# XL, LineageOS 22.2, Chrome 153): the flag is accepted, but the *only*
# thing that ever appears is a Linux ABSTRACT unix socket named
# "chrome_devtools_remote" (`cat /proc/net/unix | grep devtools` is the way
# to confirm this on any Android device — look for the `@chrome_devtools_
# remote` line, the `@` marks it abstract). `adb forward tcp:PORT
# localabstract:chrome_devtools_remote` is the standard USB-tethered answer
# to this; latch-android-bridge.py is the SSH-reachable equivalent for a
# headless/remote anchor with no USB cable involved.
#
# Also different from desktop Chrome: Android has no `--headless=new` mode
# at all (it is a real mobile browser UI, always). This is actually a
# *fingerprint win*, not a limitation — a real Android Chrome instance sets
# a real mobile User-Agent and never advertises "HeadlessChrome" in the
# first place (confirmed live: `/json/version` returned a stock
# "Mozilla/5.0 (Linux; Android 10; K) ... Mobile Safari/537.36" string with
# no bridging, no UA override needed). What desktop Latch does with a UA
# flag, Android does for free by being a real phone.
#
# Usage: ./latch-start-android.sh <anchor_ssh_host> [cdp_port]
#
# Requires: root on the anchor (`su -c` used throughout — same requirement
# the existing `pixy` toolkit already assumes for this class of device),
# Chrome installed, Termux's python3 (ships with any standard Termux
# install, used only as an unprivileged TCP<->unix-socket relay — see
# latch-android-bridge.py's own header for why this is the minimal-
# privilege way to do it rather than something more invasive like a
# custom native proxy).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANCHOR="${1:?usage: latch-start-android.sh <ssh_host> [cdp_port]}"
CDP_PORT="${2:-9333}"
CHROME_PKG="${LATCH_ANDROID_CHROME_PKG:-com.android.chrome}"
CHROME_LAUNCH_ACTIVITY="${LATCH_ANDROID_CHROME_ACTIVITY:-com.google.android.apps.chrome.Main}"
BRIDGE_REMOTE_PATH="/data/local/tmp/latch_android_bridge.py"
BRIDGE_LOG="/data/local/tmp/latch_android_bridge.log"
CMDLINE_FILE="/data/local/tmp/chrome-command-line"

echo "[latch] Android anchor: stopping any previous Latch bridge/Chrome state..."
ssh "$ANCHOR" "su -c 'pkill -f ${BRIDGE_REMOTE_PATH} 2>/dev/null; am force-stop ${CHROME_PKG} 2>/dev/null; true'" || true

echo "[latch] Android anchor: writing Chrome flags file (enables the DevTools abstract socket)..."
# The leading "_" is a required placeholder argv[0] — Chrome's command-line
# file format on Android ignores the first token and reads flags from the
# rest, a quirk documented nowhere officially but confirmed by every working
# example (chromium's own chrome_command_line.txt tooling included).
ssh "$ANCHOR" "su -c \"sh -c 'echo \\\"_ --remote-debugging-port=0 --disable-fre --no-first-run --disable-blink-features=AutomationControlled\\\" > ${CMDLINE_FILE} && chmod 664 ${CMDLINE_FILE}'\""

echo "[latch] Android anchor: pushing the TCP<->unix-socket bridge..."
ssh "$ANCHOR" "cat > /data/data/com.termux/files/home/.latch_android_bridge.py" < "${SELF_DIR}/latch-android-bridge.py"
ssh "$ANCHOR" "su -c 'cp /data/data/com.termux/files/home/.latch_android_bridge.py ${BRIDGE_REMOTE_PATH} && chmod 644 ${BRIDGE_REMOTE_PATH}'"

echo "[latch] Android anchor: launching Chrome with the DevTools flags active..."
ssh "$ANCHOR" "su -c 'am start -n ${CHROME_PKG}/${CHROME_LAUNCH_ACTIVITY} -d about:blank'"
sleep 2

echo "[latch] Android anchor: starting the CDP bridge on 127.0.0.1:${CDP_PORT}..."
# No `disown` — verified live against a real device (toybox `sh`, not bash,
# is what Termux's `su -c` invokes here) that `disown` is not a builtin and
# fails with "inaccessible or not found". `nohup ... &` on its own is
# sufficient: the backgrounded process survives the parent shell's exit
# once this ssh command returns, same as every other backgrounded call in
# this repo's shell scripts.
ssh "$ANCHOR" "su -c 'nohup /data/data/com.termux/files/usr/bin/python3 ${BRIDGE_REMOTE_PATH} ${CDP_PORT} chrome_devtools_remote > ${BRIDGE_LOG} 2>&1 &
sleep 1
echo started'"

echo "[latch] waiting for CDP on ${ANCHOR}:${CDP_PORT} (via bridge)..."
for _ in $(seq 1 10); do
  sleep 1
  VER=$(ssh "$ANCHOR" "curl -s http://127.0.0.1:${CDP_PORT}/json/version" 2>/dev/null || true)
  if echo "$VER" | grep -q webSocketDebuggerUrl; then
    echo "[latch] Android bridge is up:"
    echo "$VER" | grep -E 'Browser|User-Agent' | sed 's/^/  /'
    echo "[latch] launched. Next: latch-tunnel.sh ${ANCHOR} ${CDP_PORT}"
    exit 0
  fi
done

echo "[latch] ERROR: CDP bridge did not come up. Check on-device: ssh ${ANCHOR} \"su -c 'cat ${BRIDGE_LOG}'\"" >&2
exit 1
