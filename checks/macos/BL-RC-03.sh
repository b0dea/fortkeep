#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-RC-03
# Exit 1 from the login shell means "no git there"; any other failure is undecided.
out="$(devward_shell_probe zsh-login 'command -v git')"; rc=$?
case "$rc" in
  0) g="$(printf '%s\n' "$out" | tail -n 1)" ;;
  1) g="" ;;
  *) devward_result "$ID" ERROR "couldn't start your login shell (zsh -lc) to find git" "Timed out or a start-up file failed"; exit 0 ;;
esac
case "$g" in /*) ;; *) g="$(command -v git)" ;; esac
{ [ -n "$g" ] && [ -x "$g" ]; } || { devward_result "$ID" ERROR "git not found" ""; exit 0; }
devward_needs_clt "$g" && { devward_result "$ID" NA "git isn't installed: /usr/bin/git needs Apple's Command Line Tools" "To use git, type xcode-select --install in the Terminal app"; exit 0; }
# Exit 1 means unset; any other failure (a malformed ~/.gitconfig) is undecided.
gcfg() { out="$("$g" config --global "$@" 2>/dev/null)"; }
bad() { devward_result "$ID" ERROR "couldn't read your global git config" "Fix or move ~/.gitconfig, then run the check again"; exit 0; }
gcfg --get push.default; rc=$?
case "$rc" in 0) pd="$out" ;; 1) pd="" ;; *) bad ;; esac
gcfg --get-regexp '^alias\.'; rc=$?
case "$rc" in 0) aliases="$out" ;; 1) aliases="" ;; *) bad ;; esac
force=""; n=0
while read -r key val; do
  [ -n "$key" ] || continue
  if printf '%s' "$val" | grep -Eq 'push.*(-f([[:space:]]|$)|--force)'; then force="$force ${key#alias.}"; n=$((n + 1)); fi
done <<EOF
$aliases
EOF
# A timed-out probe is undecided, never zero aliases.
shell_aliases="$(devward_shell_probe zsh-interactive alias)"; rc=$?
[ "$rc" -eq 0 ] || { devward_result "$ID" ERROR "couldn't read your shell's aliases (interactive zsh)" "Timed out or a start-up file failed"; exit 0; }
while IFS= read -r line; do
  case "$line" in *=*) ;; *) continue ;; esac
  if printf '%s' "$line" | grep -Eq "git[[:space:]]+push.*(-f([[:space:]'\"]|\$)|--force)"; then force="$force ${line%%=*}"; n=$((n + 1)); fi
done <<EOF
$shell_aliases
EOF
problems=""
[ "$pd" = simple ] || problems="push.default is ${pd:-not set}: set it to simple (git's built-in default doesn't count)."
[ "$n" -gt 0 ] && problems="$problems Force-push aliases:$force."
if [ -z "$problems" ]; then devward_result "$ID" PASS "push.default=simple; no force-push aliases"
else devward_result "$ID" FAIL "push.default=${pd:-unset}; $n force-push alias(es)" "${problems# }"; fi
