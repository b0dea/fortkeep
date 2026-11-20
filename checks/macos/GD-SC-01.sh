#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=GD-SC-01
low=""; unknown=""; total=0
while IFS= read -r t; do
  [ -n "$t" ] || continue
  total=$((total + 1))
  out="$(fortkeep_shell_probe "$t" 'printf "AGE=%s\n" "${SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS-}"')"; rc=$?
  line="$(printf '%s\n' "$out" | tail -n 1)"
  # A timeout, a crash or a broken start-up file is undecided, not "not set".
  if [ "$rc" -ne 0 ] || [ "${line#AGE=}" = "$line" ]; then unknown="$unknown, $(fortkeep_shell_label "$t")"; continue; fi
  a="${line#AGE=}"
  case "$a" in ''|*[!0-9]*) low="$low, $(fortkeep_shell_label "$t") (not set)" ;; *) [ "$a" -ge 168 ] || low="$low, $(fortkeep_shell_label "$t") ($a h)" ;; esac
done <<EOT
$(fortkeep_shell_types)
EOT
if [ -n "$low" ]; then fortkeep_result "$ID" FAIL "Age gate below 168 hours in some shell types" "${low#, }${unknown:+. Timed out or failed to start: ${unknown#, }}"
elif [ -n "$unknown" ]; then fortkeep_result "$ID" ERROR "Could not read the age gate in every shell type" "Timed out or failed to start: ${unknown#, }"
else fortkeep_result "$ID" PASS "Age gate at 168 hours or more in all $total shell types"; fi
