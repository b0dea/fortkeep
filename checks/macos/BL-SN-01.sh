#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-SN-01
out="$(fortkeep_shell_probe zsh-login 'for t in osv-scanner pip-audit gitleaks cosign shellcheck actionlint; do command -v "$t" >/dev/null || echo "missing $t"; done; echo "brew $(command -v brew)"; echo fortkeep-done')"; rc=$?
[ "$rc" -eq 0 ] || out=""
case "$out" in *fortkeep-done*) ;; *) fortkeep_result "$ID" ERROR "Could not look for the scanners" "The login shell did not finish (it failed or took too long)"; exit 0 ;; esac
missing="$(printf '%s\n' "$out" | sed -n 's/^missing //p' | paste -sd' ' -)"
b="$(printf '%s\n' "$out" | sed -n 's/^brew //p' | tail -n 1)"
if [ -n "$b" ]; then
  real="$(fortkeep_timeout 10 perl -MCwd=abs_path -e 'print abs_path($ARGV[0]) // ""' "$b" 2>/dev/null)"
  case "$real" in /*) ;; *) fortkeep_result "$ID" ERROR "Could not find where Homebrew is installed" "brew is at $(fortkeep_tilde "$b") but its real location could not be resolved"; exit 0 ;; esac
  root="$(dirname "$(dirname "$real")")"
  [ -f "$root/Library/Homebrew/cmd/vulns.rb" ] || missing="$missing brew-vulns"
fi
missing="${missing# }"
if [ -z "$missing" ]; then fortkeep_result "$ID" PASS "osv-scanner, pip-audit, gitleaks, cosign, shellcheck and actionlint are installed${b:+, and brew vulns works}"
else fortkeep_result "$ID" FAIL "Some scanners are missing" "Missing: $(printf '%s' "$missing" | sed 's/ /, /g; s/brew-vulns/brew vulns (update Homebrew)/')"; fi
