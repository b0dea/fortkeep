#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-03
case "$(spctl --status 2>/dev/null)" in
  *"assessments enabled"*) devward_result "$ID" PASS "Gatekeeper: on" ;;
  *"assessments disabled"*) devward_result "$ID" FAIL "Gatekeeper: off" "Needs admin rights: the agent will give you the command to run" ;;
  *) devward_result "$ID" ERROR "spctl gave an unexpected answer" "" ;;
esac
