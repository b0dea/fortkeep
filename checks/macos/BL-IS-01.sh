#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-IS-01
found=""
for a in OrbStack UTM Docker "Parallels Desktop" "VMware Fusion" "Podman Desktop" "Rancher Desktop"; do
  fortkeep_app "$a" >/dev/null && found="$found, $a"
done
out="$(fortkeep_shell_probe zsh-login 'for t in colima limactl podman tart multipass; do command -v "$t" >/dev/null && echo "$t"; done; echo fortkeep-done')"; rc=$?
[ "$rc" -eq 0 ] || out=""
clis="$(printf '%s\n' "$out" | grep -v '^fortkeep-done$')"
[ -n "$clis" ] && found="$found, $(printf '%s\n' "$clis" | paste -sd, - | sed 's/,/, /g')"
if [ -n "$found" ]; then fortkeep_result "$ID" PASS "Found: ${found#, }"
else
  case "$out" in *fortkeep-done*) fortkeep_result "$ID" FAIL "No VM or container tool for running untrusted code" ;;
    *) fortkeep_result "$ID" ERROR "Could not look for VM and container commands" "No known app was found and the login shell did not finish" ;; esac
fi
