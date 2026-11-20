#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=OV-VL-02
# `varlock telemetry disable` writes telemetryDisabled here. Only that key is read: the file also holds an id.
CONF="$HOME/.config/varlock/config.json"
if [ -f "$CONF" ]; then
  off="$(jq -r 'if type == "object" then (.telemetryDisabled == true) else error end' "$CONF" 2>/dev/null)" \
    || { fortkeep_result "$ID" ERROR "Could not read varlock's settings" "$(fortkeep_tilde "$CONF") is not valid JSON"; exit 0; }
  [ "$off" = true ] && { fortkeep_result "$ID" PASS "varlock's telemetry is off"; exit 0; }
fi
out="$(fortkeep_shell_probe zsh-login 'echo "vl $(command -v varlock)"; echo fortkeep-done')"; rc=$?
[ "$rc" -eq 0 ] || out=""
case "$out" in *fortkeep-done*) ;; *) fortkeep_result "$ID" ERROR "Could not look for varlock" "The login shell did not finish (it failed or took too long)"; exit 0 ;; esac
case "$(printf '%s\n' "$out" | sed -n 's/^vl //p' | tail -n 1)" in
  /*) fortkeep_result "$ID" FAIL "varlock's telemetry is on (its default)" "Run varlock telemetry disable in Terminal" ;;
  *) fortkeep_result "$ID" NA "varlock is not installed" ;;
esac
