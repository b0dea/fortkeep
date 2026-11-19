#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/baselines.sh"
ID=BL-OS-06
ports="22 3283 5900 445 548"
listening=""; undecided=""
read_ok=1; socks="$(devward_listen_sockets)" || { read_ok=0; undecided="netstat gave no output"; }
while IFS="$(printf '\t')" read -r _ port _; do
  [ -n "$port" ] || continue
  case " $ports " in *" $port "*) ;; *) continue ;; esac
  case " $listening " in *" $port "*) ;; *) listening="$listening $port" ;; esac
done <<EOF2
$socks
EOF2
if air="$(defaults -currentHost read com.apple.controlcenter AirplayReceiverEnabled 2>&1)"; then :
else
  if devward_defaults_unset "$air"; then air=1; else air=unknown; undecided="${undecided:+$undecided; }could not read AirPlay Receiver setting"; fi
fi
names=""
for p in $listening; do
  case $p in
    22) n="Remote Login" ;; 3283|5900) n="Screen Sharing / Remote Management" ;; 445|548) n="File Sharing" ;;
  esac
  case "$names" in *"$n"*) ;; *) names="$names, $n" ;; esac
done
case "$air" in 0|unknown) ;; *) names="$names, AirPlay Receiver" ;; esac
names="${names#, }"
case "$air" in 0) as=off ;; unknown) as=unknown ;; *) as=on ;; esac
lp="${listening:- none}"; [ "$read_ok" -eq 1 ] || lp=" unknown"
ev="sharing ports listening:$lp; AirPlay Receiver: $as"
# A sharing service found on is a FAIL even when the other half couldn't be read.
if [ -n "$names" ]; then devward_result "$ID" FAIL "$ev" "Turn off: $names (System Settings → General → Sharing, and General → AirDrop & Handoff)${undecided:+. Undecided: $undecided}"
elif [ -n "$undecided" ]; then devward_result "$ID" ERROR "$undecided" "$ev"
else devward_result "$ID" PASS "$ev"; fi
