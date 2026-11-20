# shellcheck shell=sh
# fortkeep: Safe Chain's shims first on PATH and its age gate pinned. Safe to load twice.
case "${SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS:-}" in ''|*[!0-9]*) SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168 ;; esac
[ "$SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS" -ge 168 ] || SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168
export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS
_fortkeep_rest="$(printf '%s' "$PATH" | /usr/bin/tr ':' '\n' | /usr/bin/grep -vxF -e "$HOME/.safe-chain/shims" -e "$HOME/.safe-chain/bin" -e '' | /usr/bin/paste -sd: -)"
PATH="$HOME/.safe-chain/shims:$HOME/.safe-chain/bin${_fortkeep_rest:+:$_fortkeep_rest}"
export PATH
unset _fortkeep_rest
