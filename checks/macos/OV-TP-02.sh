#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=OV-TP-02
[ -x "$HOME/.safe-chain/shims/npm" ] || { devward_result "$ID" FAIL "Safe Chain isn't installed" "Install it first (BL-SC-01)"; exit 0; }
t="${DEVWARD_VERIFY_TIMEOUT:-45}"
out="$(DEVWARD_SHELL_TIMEOUT="$t" devward_shell_probe zsh 'echo started; npm safe-chain-verify >/dev/null 2>&1; echo "rc=$?"')"; rc=$?
last="$(printf '%s\n' "$out" | tail -n 1)"
if [ "$rc" -eq 142 ] && ! printf '%s\n' "$out" | grep -qx started; then
  devward_result "$ID" ERROR "The non-interactive shell did not start within ${t}s" "A zsh start-up file (~/.zshenv) may be slow or waiting for input"
elif [ "$rc" -eq 142 ]; then
  devward_result "$ID" FAIL "safe-chain-verify did not finish in ${t}s from a non-interactive shell" "Behind TLS inspection Safe Chain needs the CA bundle in the environment (OV-TP-01)"
elif [ "$rc" -ne 0 ]; then
  devward_result "$ID" ERROR "The non-interactive shell failed to start (exit $rc)" "Check your zsh start-up files"
elif [ "$last" = "rc=0" ]; then
  devward_result "$ID" PASS "safe-chain-verify succeeds from a non-interactive shell"
elif [[ "$last" == rc=* ]]; then
  devward_result "$ID" FAIL "safe-chain-verify fails from a non-interactive shell" "Run zsh -c 'npm safe-chain-verify' in Terminal to see why"
else
  devward_result "$ID" ERROR "The non-interactive shell gave no answer" "A zsh start-up file may end the shell early"
fi
