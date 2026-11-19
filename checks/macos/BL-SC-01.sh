#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SC-01
sc="$HOME/.safe-chain"
missing=""
[ -x "$sc/bin/safe-chain" ] || missing="$missing safe-chain"
for s in npm pip3; do [ -x "$sc/shims/$s" ] || missing="$missing shims/$s"; done
if [ -n "$missing" ]; then
  devward_result "$ID" FAIL "Safe Chain or its --ci shims are missing:$missing" "Install it as in the lesson, including the --ci step"
  exit 0
fi
t="${DEVWARD_VERIFY_TIMEOUT:-30}"
devward_timeout "$t" "$sc/shims/npm" safe-chain-verify </dev/null >/dev/null 2>&1
rc=$?
case "$rc" in
  0) ;;
  142) devward_result "$ID" ERROR "Safe Chain and its shims are installed" "safe-chain-verify did not finish in ${t}s"; exit 0 ;;
  *) devward_result "$ID" FAIL "Safe Chain is installed, but safe-chain-verify failed (exit $rc)" "Run npm safe-chain-verify in Terminal to see why"; exit 0 ;;
esac
# The proof the baseline asks for: Safe Chain's harmless test package must be refused. It runs in an empty
# folder that is removed afterwards, so even a package that gets through is gone again. Its own package.json
# keeps npm from installing into a project further up, and --ignore-scripts keeps a package that got through from
# running anything; Safe Chain still checks the package by name before npm runs.
t="${DEVWARD_TEST_PACKAGE_TIMEOUT:-45}"
d="$(mktemp -d "${TMPDIR:-/tmp}/devward-safe-chain-test.XXXXXX")" || {
  devward_result "$ID" ERROR "Could not create a temporary folder to try the test package in" "Check that ${TMPDIR:-/tmp} is writable"; exit 0; }
trap 'rm -rf "$d"' EXIT
printf '{"private": true}\n' > "$d/package.json"
out="$(cd "$d" && devward_timeout "$t" "$sc/shims/npm" install --no-save --ignore-scripts safe-chain-test </dev/null 2>&1)"
rc=$?
if [ -e "$d/node_modules/safe-chain-test" ] || [ "$rc" -eq 0 ]; then
  devward_result "$ID" FAIL "Safe Chain did not refuse the test package" "npm install --no-save --ignore-scripts safe-chain-test went through; run it in Terminal to see why"
elif [ "$rc" -eq 142 ]; then
  devward_result "$ID" ERROR "Safe Chain's verify says OK, but the test package install did not finish in ${t}s" "Check the network, then run npm install --no-save --ignore-scripts safe-chain-test in Terminal"
# Safe Chain's own refusal message: any other failure (no network, npm itself broken) proves nothing.
elif printf '%s\n' "$out" | grep -q 'Exiting without installing malicious packages'; then
  devward_result "$ID" PASS "Safe Chain and its shims are installed; safe-chain-verify says OK and the test package was refused"
else
  devward_result "$ID" ERROR "The test package install failed without Safe Chain's refusal (exit $rc)" "Check the network, then run npm install --no-save --ignore-scripts safe-chain-test in Terminal"
fi
