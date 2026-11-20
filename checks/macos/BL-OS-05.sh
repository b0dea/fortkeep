#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-05
dom=/Library/Preferences/com.apple.SoftwareUpdate
off=""; ev=""
rd() {  # sets v; unset only when defaults says the key was never set, else ERROR
  v="$(defaults read "$dom" "$1" 2>&1)" && return
  if fortkeep_defaults_unset "$v"; then v=default; else fortkeep_result "$ID" ERROR "could not read $1" ""; exit 0; fi
}
for k in AutomaticCheckEnabled AutomaticDownload CriticalUpdateInstall ConfigDataInstall; do
  rd "$k"
  ev="$ev$k=$v "
  [ "$v" = 0 ] && off="$off $k"
done
rd AutomaticallyInstallMacOSUpdates; inst="$v"
ev="${ev}AutomaticallyInstallMacOSUpdates=$inst"
if [ -z "$off" ]; then
  fortkeep_result "$ID" PASS "$ev" "'default' = not set; macOS keeps checking, downloading and security responses on by default"
else
  fortkeep_result "$ID" FAIL "$ev" "Switched off:$off. Turn them on in System Settings → General → Software Update → Automatic Updates"
fi
