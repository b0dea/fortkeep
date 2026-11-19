#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-01
out="$(fdesetup isactive 2>/dev/null)"
case "$out" in
  true) devward_result "$ID" PASS "FileVault: On" ;;
  false) devward_result "$ID" FAIL "FileVault: Off" "Turn it on in System Settings → Privacy & Security → FileVault" ;;
  *) devward_result "$ID" ERROR "fdesetup gave an unexpected answer" "" ;;
esac
