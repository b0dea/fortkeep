#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-01
out="$(fdesetup isactive 2>/dev/null)"
case "$out" in
  true) fortkeep_result "$ID" PASS "FileVault: On" ;;
  false) fortkeep_result "$ID" FAIL "FileVault: Off" "Turn it on in System Settings → Privacy & Security → FileVault" ;;
  *) fortkeep_result "$ID" ERROR "fdesetup gave an unexpected answer" "" ;;
esac
