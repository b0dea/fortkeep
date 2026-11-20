#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-SE-01
# The SSH agents that keep keys out of ~/.ssh, by app and agent socket (Bitwarden's differs between its download and
# its Mac App Store version). Each socket path comes from the vendor's own documentation or source.
AGENTS="1Password	1Password	${FORTKEEP_OP_SOCK:-$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock}
Secretive	Secretive	${FORTKEEP_SECRETIVE_SOCK:-$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh}
Bitwarden	Bitwarden	${FORTKEEP_BW_SOCK:-$HOME/.bitwarden-ssh-agent.sock}
Bitwarden	Bitwarden	${FORTKEEP_BW_SOCK:-$HOME/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock}"
real() { perl -MCwd=abs_path -e 'print abs_path($ARGV[0]) // ""' "$1" 2>/dev/null; }
installed=""; on=""; socks=""
while IFS="$(printf '\t')" read -r name app sock; do
  fortkeep_app "$app" >/dev/null || continue
  case ", $installed, " in *", $name, "*) ;; *) installed="$installed, $name" ;; esac
  [ -S "$sock" ] || continue
  case ", $on, " in *", $name, "*) ;; *) on="$on, $name" ;; esac
  socks="$socks$name	$(real "$sock")"$'\n'
done <<EOF
$AGENTS
EOF
installed="${installed#, }"; on="${on#, }"
[ -n "$installed" ] || { fortkeep_result "$ID" FAIL "1Password, Secretive and Bitwarden are not installed" "Install one of them and turn on its SSH agent, as the lesson shows"; exit 0; }
[ -n "$on" ] || { fortkeep_result "$ID" FAIL "The $installed SSH agent is off" "Turn it on in the app's settings, as the lesson shows"; exit 0; }
agent_of() {  # PATH — the name of the running agent whose socket PATH is, or nothing
  local p; p="$(real "$1")"; [ -n "$p" ] || return 1
  printf '%s' "$socks" | awk -F'\t' -v p="$p" '$2 == p { print $1; exit }'
}
# A private ~/.ssh/config is never handed to ssh, which would read it and run its Match exec lines.
cfg=/dev/null; priv=""
if fortkeep_is_private "$HOME/.ssh/config"; then priv=1
elif [ -f "$HOME/.ssh/config" ]; then cfg="$HOME/.ssh/config"; fi
out="$(fortkeep_timeout "$FORTKEEP_SHELL_TIMEOUT" ssh -F "$cfg" -G github.com 2>/dev/null </dev/null)"; rc=$?
[ "$rc" -eq 142 ] && { fortkeep_result "$ID" ERROR "ssh took too long to read its config" "A Match exec line in ~/.ssh/config may be hanging"; exit 0; }
sshrc=$rc  # any other failure leaves IdentityAgent unknown: only SSH_AUTH_SOCK can still decide
ia="$(printf '%s\n' "$out" | awk 'tolower($1) == "identityagent" { sub(/^[^ ]+ /, ""); print; exit }')"
ia="${ia#\"}"; ia="${ia%\"}"
case "$ia" in '~'/*) ia="$HOME/${ia#\~/}" ;; esac
if [ "$sshrc" -eq 0 ] && [ -n "$ia" ] && [ "$ia" != none ] && a="$(agent_of "$ia")" && [ -n "$a" ]; then
  fortkeep_result "$ID" PASS "ssh uses the $a agent (IdentityAgent)"; exit 0
fi
pout="$(fortkeep_shell_probe zsh 'printf "sock=%s\n" "$SSH_AUTH_SOCK"; echo fortkeep-done')"; rc=$?
[ "$rc" -eq 0 ] || pout=""
case "$pout" in *fortkeep-done*) ;; *) fortkeep_result "$ID" ERROR "Could not read SSH_AUTH_SOCK from zsh" "The shell (zsh -c) did not finish (it failed or took too long)"; exit 0 ;; esac
as="$(printf '%s\n' "$pout" | sed -n 's/^sock=//p' | tail -n 1)"
if [ -n "$as" ] && a="$(agent_of "$as")" && [ -n "$a" ]; then fortkeep_result "$ID" PASS "ssh uses the $a agent (SSH_AUTH_SOCK)"
elif [ -n "$priv" ]; then fortkeep_result "$ID" ERROR "Could not check the ssh config" "a private folder was excluded"
elif [ "$sshrc" -ne 0 ]; then fortkeep_result "$ID" ERROR "ssh could not read its config (exit $sshrc)" "Run ssh -G github.com in Terminal to see the error in ~/.ssh/config"
else fortkeep_result "$ID" FAIL "The $on SSH agent is on, but ssh doesn't use it" "Add the IdentityAgent line to ~/.ssh/config as shown in the lesson"; fi
