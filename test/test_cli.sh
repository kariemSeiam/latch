#!/usr/bin/env bash
# test_cli.sh — dependency-free smoke tests for the `latch` dispatcher.
# Does not require a real anchor device; only exercises argument parsing,
# help output, and error paths that don't need network access.
#
# Usage: ./test/test_cli.sh
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LATCH="${SELF_DIR}/latch"
PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2"; shift 2
  "$@" >/tmp/latch-test-out 2>&1
  local actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "  ok   - ${desc}"
    PASS=$((PASS+1))
  else
    echo "  FAIL - ${desc} (expected exit ${expected}, got ${actual})"
    sed 's/^/         /' /tmp/latch-test-out
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2"; shift 2
  if "$@" 2>&1 | grep -qF "$needle"; then
    echo "  ok   - ${desc}"
    PASS=$((PASS+1))
  else
    echo "  FAIL - ${desc} (expected to find: ${needle})"
    FAIL=$((FAIL+1))
  fi
}

echo "== latch CLI dispatcher =="
assert_exit "no args prints help, exits 0" 0 "$LATCH"
assert_exit "help prints help, exits 0" 0 "$LATCH" help
assert_exit "--help prints help, exits 0" 0 "$LATCH" --help
assert_exit "unknown subcommand exits non-zero" 1 "$LATCH" totally-bogus-command
assert_contains "help lists all five verbs" "doctor" "$LATCH" help
assert_contains "help lists 'up' composite command" "up      <anchor>" "$LATCH" help

echo "== argument validation (no anchor reachability needed) =="
assert_exit "doctor with no anchor arg fails fast" 1 bash -c "'${SELF_DIR}/bin/latch-doctor.sh'"
assert_exit "start with no anchor arg fails fast" 1 bash -c "'${SELF_DIR}/bin/latch-start.sh'"
assert_exit "tunnel with no anchor arg fails fast" 1 bash -c "'${SELF_DIR}/bin/latch-tunnel.sh'"
assert_exit "status with no anchor arg fails fast" 1 bash -c "'${SELF_DIR}/bin/latch-status.sh'"
assert_exit "stop with no anchor arg fails fast" 1 bash -c "'${SELF_DIR}/bin/latch-stop.sh'"

echo
echo "${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
