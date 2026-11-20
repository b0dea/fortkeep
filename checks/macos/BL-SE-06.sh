#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-SE-06
out="$(fortkeep_shell_probe zsh-login 'echo "gl $(command -v gitleaks)"; echo "git $(command -v git)"; echo fortkeep-done')"; rc=$?
[ "$rc" -eq 0 ] || out=""
case "$out" in *fortkeep-done*) ;; *) fortkeep_result "$ID" ERROR "Could not look for gitleaks and git" "The login shell (zsh -lc) did not finish (it failed or took too long)"; exit 0 ;; esac
gl="$(printf '%s\n' "$out" | sed -n 's/^gl //p' | tail -n 1)"
case "$gl" in /*) ;; *) fortkeep_result "$ID" FAIL "gitleaks is not installed"; exit 0 ;; esac
g="$(printf '%s\n' "$out" | sed -n 's/^git //p' | tail -n 1)"
case "$g" in /*) ;; *) g="$(command -v git)" ;; esac
{ [ -n "$g" ] && [ -x "$g" ]; } || { fortkeep_result "$ID" ERROR "git not found" "gitleaks runs as a git hook, so git is needed to check it"; exit 0; }
fortkeep_needs_clt "$g" && { fortkeep_result "$ID" NA "git isn't installed: /usr/bin/git needs Apple's Command Line Tools" "To use git, type xcode-select --install in the Terminal app"; exit 0; }
v="$("$g" --version 2>/dev/null | awk '{print $3}')"
[ -n "$v" ] || { fortkeep_result "$ID" ERROR "couldn't read git's version" "Run git --version in Terminal to see why"; exit 0; }
# Exit 1 means unset; any other failure (a malformed ~/.gitconfig) is undecided.
gcfg() { val="$("$g" config --global "$@" 2>/dev/null)"; }
bad() { fortkeep_result "$ID" ERROR "couldn't read your global git config" "Fix or move ~/.gitconfig, then run the check again"; exit 0; }
gcfg --get-regexp '^hook\..*\.event$'; rc=$?
case "$rc" in 0) events="$val" ;; 1) events="" ;; *) bad ;; esac
how=""
while read -r key ev; do
  [ "$ev" = pre-commit ] || continue
  name="${key#hook.}"; name="${name%.event}"
  gcfg --get "hook.$name.command"; rc=$?
  case "$rc" in 0) cmd="$val" ;; 1) cmd="" ;; *) bad ;; esac
  case "$cmd" in *gitleaks*) ;; *) continue ;; esac
  exe="${cmd%% *}"; case "$exe" in /*) ;; *) exe="$gl" ;; esac
  [ -x "$exe" ] && how=config
done <<EOT
$events
EOT
if [ -z "$how" ]; then
  gcfg --get core.hooksPath; rc=$?
  case "$rc" in 0) hp="$val" ;; 1) hp="" ;; *) bad ;; esac
  case "$hp" in '~'/*) hp="$HOME/${hp#\~/}" ;; esac
  [ -n "$hp" ] && [ -x "$hp/pre-commit" ] && grep -q gitleaks "$hp/pre-commit" && how=hooksPath
fi
if [ -z "$how" ]; then fortkeep_result "$ID" FAIL "gitleaks is installed but isn't a global pre-commit hook" "The agent can add it"
elif [ "$how" = config ] && ! fortkeep_version_ge "$v" 2.54; then fortkeep_result "$ID" FAIL "The gitleaks hook is configured, but git $v is older than 2.54 and doesn't run it"
else fortkeep_result "$ID" PASS "gitleaks scans every commit before it's made"; fi
