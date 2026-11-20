#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-03
case "$(spctl --status 2>/dev/null)" in
  *"assessments enabled"*) fortkeep_result "$ID" PASS "Gatekeeper: on" ;;
  *"assessments disabled"*) fortkeep_result "$ID" FAIL "Gatekeeper: off" "Needs admin rights: the agent will give you the command to run" ;;
  *) fortkeep_result "$ID" ERROR "spctl gave an unexpected answer" "" ;;
esac
