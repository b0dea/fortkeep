#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=OV-VL-01
TAP=dmno-dev/tap/varlock
out="$(fortkeep_shell_probe zsh-login 'echo "vl $(command -v varlock)"; echo "brew $(command -v brew)"; echo fortkeep-done')"; rc=$?
[ "$rc" -eq 0 ] || out=""
case "$out" in *fortkeep-done*) ;; *) fortkeep_result "$ID" ERROR "Could not look for varlock" "The login shell did not finish (it failed or took too long)"; exit 0 ;; esac
v="$(printf '%s\n' "$out" | sed -n 's/^vl //p' | tail -n 1)"
b="$(printf '%s\n' "$out" | sed -n 's/^brew //p' | tail -n 1)"
case "$v" in /*) ;; *) fortkeep_result "$ID" FAIL "varlock is not installed" "Install it from its official tap in Terminal: brew install $TAP, then brew pin varlock"; exit 0 ;; esac
real="$(fortkeep_realpath "$v")"
case "$real" in
  */Cellar/varlock/*/bin/varlock) ver="${real%/bin/varlock}"; ver="${ver##*/}" ;;
  # This overlay was chosen, and a copy from anywhere else is the unverified case it exists to catch.
  *) fortkeep_result "$ID" FAIL "varlock at $(fortkeep_tilde "$v") is not installed by Homebrew" "Remove that copy, then install it from its official tap in Terminal: brew install $TAP, then brew pin varlock"; exit 0 ;;
esac
case "$b" in /*) ;; *) fortkeep_result "$ID" ERROR "varlock $ver is installed by Homebrew, but brew was not found" "Open a new Terminal and run the check again"; exit 0 ;; esac
t="${FORTKEEP_BREW_TIMEOUT:-30}"
names="$(fortkeep_timeout "$t" "$b" list --formula --full-name </dev/null 2>/dev/null)"; rc1=$?
pinned="$(fortkeep_timeout "$t" "$b" list --pinned </dev/null 2>/dev/null)"; rc2=$?
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] || { fortkeep_result "$ID" ERROR "varlock $ver is installed by Homebrew, but brew could not list its formulae" "brew list failed or took longer than ${t}s"; exit 0; }
full="$(printf '%s\n' "$names" | grep -E '(^|/)varlock$' | head -n 1)"
if [ "$full" != "$TAP" ]; then
  fortkeep_result "$ID" FAIL "varlock $ver comes from ${full:-an unknown formula}, not the official tap" "Reinstall it from $TAP, which installs the official release checked against its sha256"
elif printf '%s\n' "$pinned" | grep -Eqx "(dmno-dev/tap/)?varlock"; then
  fortkeep_result "$ID" PASS "varlock $ver from $TAP, pinned"
else
  fortkeep_result "$ID" FAIL "varlock $ver from $TAP is not pinned" "brew upgrade replaces it without your review: run brew pin varlock in Terminal, and brew unpin it when you have reviewed a new release"
fi
