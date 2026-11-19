#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-04
out="$(csrutil status 2>/dev/null)"
case "$out" in
  *"status: enabled."*) devward_result "$ID" PASS "SIP: on" ;;
  *"status: disabled."*|*"Custom Configuration"*) devward_result "$ID" FAIL "SIP: off or customised" "Can only be turned on from macOS Recovery; the agent will walk you through it" ;;
  *) devward_result "$ID" ERROR "csrutil gave an unexpected answer" "" ;;
esac
