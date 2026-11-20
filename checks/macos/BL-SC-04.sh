#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-SC-04
# One line per shell: age | exclusions | malware list or custom registries. Values never leave the shell except these.
snip='printf "%s|%s|%s\n" "${SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS-}" "${SAFE_CHAIN_MINIMUM_PACKAGE_AGE_EXCLUSIONS-}${SAFE_CHAIN_NPM_MINIMUM_PACKAGE_AGE_EXCLUSIONS-}" "${SAFE_CHAIN_MALWARE_LIST_BASE_URL-}${SAFE_CHAIN_NPM_CUSTOM_REGISTRIES-}${SAFE_CHAIN_PIP_CUSTOM_REGISTRIES-}"'
low=""; weak=""; unknown=""; lowest=""
for t in zsh zsh-login clean-zsh-login zsh-interactive; do
  out="$(fortkeep_shell_probe "$t" "$snip")"; rc=$?
  line="$(printf '%s\n' "$out" | tail -n 1)"
  # A timeout, a crash or a broken start-up file is undecided, not "not set".
  if [ "$rc" -ne 0 ] || [ "${line#*|}" = "$line" ]; then unknown="$unknown, $(fortkeep_shell_label "$t")"; continue; fi
  age="${line%%|*}"; rest="${line#*|}"
  case "$age" in
    ''|*[!0-9]*) low="$low, $(fortkeep_shell_label "$t") (not set)" ;;
    *) [ "$age" -ge 48 ] || low="$low, $(fortkeep_shell_label "$t") ($age h)"
       if [ -z "$lowest" ] || [ "$age" -lt "$lowest" ]; then lowest="$age"; fi ;;
  esac
  [ "$rest" = "|" ] || weak="$weak, $(fortkeep_shell_label "$t")"
done
# Safe Chain also reads its config file, the older ~/.aikido one when there is none, and adds the exclusions and
# registries there to the environment's; its malware list URL counts when the environment sets none
# (https://github.com/AikidoSec/safe-chain/blob/1.5.29/packages/safe-chain/src/config/configFile.js and settings.js,
# checked 2026-11-20). Only how many such entries there are leaves jq.
cfg="$HOME/.safe-chain/config.json"; [ -e "$cfg" ] || cfg="$HOME/.aikido/config.json"
unread=""
if [ -e "$cfg" ]; then
  n="$(jq -r 'if type == "object" then [(.malwareListBaseUrl | strings | select(length > 0)),
    ((.npm, .pip) | objects | (.customRegistries, .minimumPackageAgeExclusions) | arrays | .[] | strings | select(length > 0))] | length
    else 0 end' "$cfg" 2>/dev/null)"
  case "$n" in
    ''|*[!0-9]*) unread="$(fortkeep_tilde "$cfg")" ;;
    0) ;;
    *) weak="$weak, $(fortkeep_tilde "$cfg")" ;;
  esac
fi
if [ -n "$low$weak" ]; then
  note=""
  [ -n "$low" ] && note="Below 48 hours or not set in: ${low#, } (Safe Chain's own default doesn't count: a repo's .aikido file can lower it)."
  [ -n "$weak" ] && note="$note Exclusions, custom registries or another malware list weaken the gate in: ${weak#, }."
  [ -n "$unknown" ] && note="$note Timed out or failed to start: ${unknown#, }."
  [ -n "$unread" ] && note="$note Could not read $unread as JSON."
  fortkeep_result "$ID" FAIL "Age gate not pinned at 48 hours or more in every zsh" "${note# }"
elif [ -n "$unknown" ]; then
  fortkeep_result "$ID" ERROR "Could not read the age gate in every zsh" "Timed out or failed to start: ${unknown#, }${unread:+. Could not read $unread as JSON}"
elif [ -n "$unread" ]; then
  fortkeep_result "$ID" ERROR "Could not read Safe Chain's config file" "$unread isn't JSON jq can read; fix or remove it, then run the check again"
else
  fortkeep_result "$ID" PASS "Age gate pinned at $lowest hours or more in zsh -c, zsh -lc, env -i zsh -lc and interactive zsh"
fi
