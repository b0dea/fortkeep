#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
. "$(dirname "$0")/../lib/agents.sh"
ID=BL-RC-02
# Exit 1 from the login shell means "no git there"; any other failure is undecided.
out="$(fortkeep_shell_probe zsh-login 'command -v git')"; rc=$?
case "$rc" in
  0) g="$(printf '%s\n' "$out" | tail -n 1)" ;;
  1) g="" ;;
  *) fortkeep_result "$ID" ERROR "couldn't start your login shell (zsh -lc) to find git" "Timed out or a start-up file failed"; exit 0 ;;
esac
case "$g" in /*) ;; *) g="$(command -v git)" ;; esac
{ [ -n "$g" ] && [ -x "$g" ]; } || { fortkeep_result "$ID" ERROR "git not found" ""; exit 0; }
fortkeep_needs_clt "$g" && { fortkeep_result "$ID" NA "git isn't installed: /usr/bin/git needs Apple's Command Line Tools" "To use git, type xcode-select --install in the Terminal app"; exit 0; }
v="$("$g" --version 2>/dev/null | awk '{print $3}')"
[ -n "$v" ] || { fortkeep_result "$ID" ERROR "couldn't read git's version" ""; exit 0; }
# Exit 1 means unset; any other failure (a malformed ~/.gitconfig) is undecided.
gcfg() { out="$("$g" config --global "$@" 2>/dev/null)"; }
bad() { fortkeep_result "$ID" ERROR "couldn't read your global git config" "Fix or move ~/.gitconfig, then run the check again"; exit 0; }
gcfg --get core.hooksPath; rc=$?
case "$rc" in 0) hp="$out" ;; 1) hp="" ;; *) bad ;; esac
case "$hp" in '~'/*) hp="$HOME/${hp#\~/}" ;; esac
gcfg --get-regexp '^hook\..*\.event$'; rc=$?
case "$rc" in 0) events="$out" ;; 1) events="" ;; *) bad ;; esac
missing=""; unread=""; viaconfig=0; scanners=""
for ev in post-checkout post-merge post-rewrite; do
  ok=0
  while read -r key val; do
    [ "$val" = "$ev" ] || continue
    name="${key#hook.}"; name="${name%.event}"
    gcfg --get "hook.$name.command"; rc=$?
    case "$rc" in 0) cmd="$out" ;; 1) cmd="" ;; *) bad ;; esac
    exe="$(fortkeep_hook_script "$cmd")"  # the scanner by name, not any program that happens to run
    if [ -n "$exe" ] && [ -x "$exe" ] && [ "$(basename "$exe")" = git-scan-new-files ]; then ok=1; viaconfig=1; scanners="$scanners$exe"$'\n'; fi
  done <<EOF
$events
EOF
  [ "$ok" -eq 1 ] && continue
  if [ -n "$hp" ] && [ -x "$hp/$ev" ] && [ ! -r "$hp/$ev" ]; then unread="$unread $ev"
  elif [ -z "$hp" ] || [ ! -x "$hp/$ev" ] || ! grep -q git-scan-new-files "$hp/$ev" 2>/dev/null; then missing="$missing $ev"; fi
done
# A core.hooksPath hook may call the scanner by any spelling: check the copy the fix installs, when there is one.
[ "$viaconfig" -eq 1 ] || [ ! -e "$HOME/.local/bin/git-scan-new-files" ] || scanners="$HOME/.local/bin/git-scan-new-files"
# An older copy misses the indicators added since, so it must match this repo's byte for byte.
stale=""; badread=""
while IFS= read -r exe; do
  [ -n "$exe" ] || continue
  cmp -s "$exe" "$FORTKEEP_REPO/fixes/files/git-scan-new-files"
  case $? in 0) ;; 1) stale="$stale"$'\n'"$(fortkeep_tilde "$exe")" ;; *) badread="$badread $(fortkeep_tilde "$exe")" ;; esac
done <<EOF
$(printf '%s' "$scanners" | awk '!s[$0]++')
EOF
if [ -n "$missing" ]; then
  fortkeep_result "$ID" FAIL "No scan hook for:$missing" "The agent can install one.${unread:+ Could not read the core.hooksPath hook for:$unread}"
elif [ "$viaconfig" -eq 1 ] && ! fortkeep_version_ge "$v" 2.54; then
  fortkeep_result "$ID" FAIL "Scan hooks are configured, but git $v is older than 2.54 and doesn't run them" "Install a newer git (brew install git) and open a new Terminal${unread:+. Could not read the core.hooksPath hook for:$unread}"
elif [ -n "$stale" ]; then
  fortkeep_result "$ID" FAIL "The installed scan hook is out of date" "$(fortkeep_join "$stale" ', ') differs from this repo's copy, so it misses newer indicators. The agent can update it (the BL-RC-02 fix)"
elif [ -n "$unread" ]; then
  fortkeep_result "$ID" ERROR "Couldn't read the core.hooksPath hook for:$unread" "Check that file's permissions, then run the check again"
elif [ -n "$badread" ]; then
  fortkeep_result "$ID" ERROR "Couldn't read the installed scan hook:$badread" "Check that file's permissions, then run the check again"
else
  note=""
  # Without Command Line Tools, /usr/bin/git opens an install dialog, so skip it.
  if [ "$viaconfig" -eq 1 ] && xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/git ]; then
    av="$(/usr/bin/git --version 2>/dev/null | awk '{print $3}')"
    fortkeep_version_ge "${av:-0}" 2.54 || note="Apps that use Apple's git ($av) skip the scan"
  fi
  fortkeep_result "$ID" PASS "A scan hook runs after checkout, merge and rewrite (git $v)" "$note"
fi
