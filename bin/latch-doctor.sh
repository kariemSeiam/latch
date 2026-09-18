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
