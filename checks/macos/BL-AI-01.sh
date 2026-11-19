#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-AI-01
where="outside an agent"; [ -n "${CLAUDECODE:-}" ] && where="from Claude Code"
got="$(PATH="$DEVWARD_USER_PATH" /usr/bin/which npm 2>/dev/null)"
if [ "$got" = "$HOME/.safe-chain/shims/npm" ]; then
  devward_result "$ID" PASS "npm is the Safe Chain shim in this run's own shell ($where)"
else
  devward_result "$ID" FAIL "npm is ${got:+$(devward_tilde "$got")}${got:-not found} in this run's own shell ($where)" "Fix BL-SC-02 and BL-SC-03, then restart the agent so it starts with the new PATH"
fi
