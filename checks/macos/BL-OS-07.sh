#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-07
out="$(fortkeep_timeout 10 sysadminctl -screenLock status 2>&1)"
case "$out" in
  *"screenLock delay is immediate"*) fortkeep_result "$ID" PASS "Screen lock: immediate" ;;
  *"screenLock delay is "*)
    d="$(printf '%s\n' "$out" | sed -n 's/.*screenLock delay is //p' | head -1)"
    fortkeep_result "$ID" FAIL "Screen lock: after $d" "System Settings → Lock Screen → Require password after screen saver begins or display is turned off → Immediately" ;;
  *"screenLock is off"*) fortkeep_result "$ID" FAIL "Screen lock: off" "System Settings → Lock Screen → Require password … → Immediately" ;;
  *) fortkeep_result "$ID" ERROR "sysadminctl gave an unexpected answer" "" ;;
esac
