#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=GD-GT-01
if [ -n "${FORTKEEP_GIT:-}" ]; then g="$FORTKEEP_GIT"
else
  g="$(fortkeep_shell_probe zsh-login 'command -v git' | tail -n 1)"
  case "$g" in /*) ;; *) g="$(command -v git)" ;; esac
fi
{ [ -n "$g" ] && [ -x "$g" ]; } || { fortkeep_result "$ID" ERROR "Could not find git" "git is not installed or not on the PATH"; exit 0; }
fortkeep_needs_clt "$g" && { fortkeep_result "$ID" NA "git isn't installed: /usr/bin/git needs Apple's Command Line Tools" "To use git, type xcode-select --install in the Terminal app"; exit 0; }
# git config --get exits 1 when the key is simply unset; anything higher means it couldn't read the config.
cfg() { fortkeep_timeout 10 "$g" config --global --get "$1" 2>/dev/null </dev/null; }
fmt="$(cfg gpg.format)"; r1=$?
key="$(cfg user.signingkey)"; r2=$?
sign="$(cfg commit.gpgsign)"; r3=$?
if [ "$r1" -gt 1 ] || [ "$r2" -gt 1 ] || [ "$r3" -gt 1 ]; then
  fortkeep_result "$ID" ERROR "Could not read the global git config" "git config failed; the file may be damaged"; exit 0
fi
bad=""
[ "$fmt" = ssh ] || bad="$bad gpg.format is ${fmt:-not set} (should be ssh)."
[ -n "$key" ] || bad="$bad No user.signingkey."
[ "$sign" = true ] || bad="$bad commit.gpgsign is ${sign:-not set} (should be true)."
case "$key" in
  '~'/*|/*) k="$key"; case "$k" in '~'/*) k="$HOME/${k#\~/}" ;; esac; [ -f "$k" ] || bad="$bad The signing key file is missing." ;;
esac
if [ -z "$bad" ]; then fortkeep_result "$ID" PASS "Commits are signed with an SSH key" "Also turn on vigilant mode on GitHub"
else fortkeep_result "$ID" FAIL "Commits aren't signed with an SSH key" "${bad# }"; fi
