#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-02
FW="${FORTKEEP_SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}"
if [ ! -x "$FW" ]; then fortkeep_result "$ID" ERROR "socketfilterfw not found" ""; exit 0; fi
gs="$("$FW" --getglobalstate 2>/dev/null)"
ss="$("$FW" --getstealthmode 2>/dev/null)"
undecided=""
case "$gs" in
  *"State = 1"*|*"State = 2"*) on=on ;;
  *"State = 0"*) on=off ;;
  *) on=unknown; undecided="socketfilterfw gave an unexpected answer about the firewall" ;;
esac
case "$ss" in
  *"stealth mode is on"*) st=on ;;
  *"stealth mode is off"*) st=off ;;
  *) st=unknown; undecided="${undecided:+$undecided; }socketfilterfw gave an unexpected answer about stealth mode" ;;
esac
ev="Firewall: $on; stealth: $st"
# Either one found off is a FAIL even when the other couldn't be read.
if [ "$on" = off ] || [ "$st" = off ]; then fortkeep_result "$ID" FAIL "$ev" "Needs admin rights: the agent will give you the commands to run${undecided:+. Undecided: $undecided}"
elif [ -n "$undecided" ]; then fortkeep_result "$ID" ERROR "$undecided" "$ev"
else fortkeep_result "$ID" PASS "$ev"; fi
