#!/usr/bin/env bash
# latch-doctor.sh — preflight checks before you ever run latch-start.sh.
# Catches the failure modes that cost real debugging time: unreachable
# anchor, password-prompting SSH, no browser binary, curl missing.
#
# Usage: ./latch-doctor.sh <anchor_ssh_host>
set -euo pipefail

ANCHOR="${1:?usage: latch-doctor.sh <ssh_host>}"
ISSUES=0

check() {
  local label="$1"; shift
  printf '  %-42s' "$label"
  if "$@" >/tmp/latch-doctor-out 2>&1; then
    echo "OK"
    return 0
  else
    echo "FAIL"
    sed 's/^/      /' /tmp/latch-doctor-out | head -3
    ISSUES=$((ISSUES+1))
    return 1
  fi
}

echo "[latch] doctor — checking local host"
check "curl present"        bash -c 'command -v curl'
check "ssh present"         bash -c 'command -v ssh'

echo "[latch] doctor — checking anchor: ${ANCHOR}"
check "ssh reachable, no password prompt" \
  bash -c "ssh -o ConnectTimeout=8 -o BatchMode=yes '${ANCHOR}' 'echo ok'"

printf '  %-42s' "anchor platform"
IS_ANDROID=0
if ssh -o BatchMode=yes "$ANCHOR" 'command -v getprop' >/dev/null 2>&1; then
  IS_ANDROID=1
  echo "Android (getprop present) — will use latch-start-android.sh"
else
  echo "desktop/Linux (no getprop)"
fi

if [ "$IS_ANDROID" -eq 1 ]; then
  printf '  %-42s' "root access (su -c) on anchor"
  if ssh -o BatchMode=yes "$ANCHOR" "su -c 'id -u'" 2>/dev/null | grep -q '^0$'; then
    echo "OK"
  else
    echo "FAIL (Latch's Android path needs root — su -c 'id -u' did not return 0)"
    ISSUES=$((ISSUES+1))
  fi

  printf '  %-42s' "Chrome installed on anchor"
  if ssh -o BatchMode=yes "$ANCHOR" "su -c 'pm path com.android.chrome'" 2>/dev/null | grep -q '^package:'; then
    echo "OK"
  else
    echo "FAIL (com.android.chrome not found; set LATCH_ANDROID_CHROME_PKG for a different Chromium-based browser)"
    ISSUES=$((ISSUES+1))
  fi

  printf '  %-42s' "Termux python3 present on anchor"
  if ssh -o BatchMode=yes "$ANCHOR" 'test -x /data/data/com.termux/files/usr/bin/python3' 2>/dev/null; then
    echo "OK"
  else
    echo "FAIL (latch-android-bridge.py needs Termux's python3 — install Termux + run it once first)"
    ISSUES=$((ISSUES+1))
  fi
else
  printf '  %-42s' "browser binary present on anchor"
  BIN=$(ssh -o BatchMode=yes "$ANCHOR" '
    for b in google-chrome google-chrome-stable chromium chromium-browser \
             /opt/brave.com/brave-origin-nightly/brave \
             /opt/brave.com/brave/brave brave-browser; do
      p=$(command -v "$b" 2>/dev/null || true)
      if [ -n "$p" ]; then echo "$p"; break; fi
      if [ -x "$b" ]; then echo "$b"; break; fi
    done
  ' 2>/dev/null || true)
  if [ -n "$BIN" ]; then
    echo "OK ($BIN)"
  else
    echo "FAIL (none of the known binaries found; set LATCH_BROWSER_BIN)"
    ISSUES=$((ISSUES+1))
  fi
fi

printf '  %-42s' "anchor has an active desktop session (info)"
if ssh -o BatchMode=yes "$ANCHOR" 'who | grep -q .' 2>/dev/null; then
  echo "yes (latch will run alongside it, isolated)"
else
echo "no (fine — latch does not need one)"
fi

echo
if [ "$ISSUES" -eq 0 ]; then
  echo "[latch] doctor: all checks passed. Run latch-start.sh."
else
  echo "[latch] doctor: ${ISSUES} issue(s) found — fix them before latch-start.sh will work reliably." >&2
  exit 1
fi
