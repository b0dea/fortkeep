#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=GD-SE-01
gh="$(fortkeep_real_cmd gh)" || { fortkeep_result "$ID" NA "GitHub CLI is not installed"; exit 0; }
errf="$(mktemp)" || { fortkeep_result "$ID" ERROR "Could not run the check" "No temporary file"; exit 0; }
trap 'rm -f "$errf"' EXIT
# Only the headers are kept: the body (with the account name) is dropped at the first blank line.
raw="$(fortkeep_timeout "${FORTKEEP_GH_TIMEOUT:-20}" "$gh" api -i user 2>"$errf" </dev/null)"; rc=$?
h="$(printf '%s\n' "$raw" | tr -d '\r' | awk 'NF == 0 { exit } { print }')"; raw=""
[ "$rc" -eq 142 ] && { fortkeep_result "$ID" ERROR "GitHub did not answer in time" "gh took too long; try again"; exit 0; }
first="$(printf '%s\n' "$h" | head -1)"
if [ -z "$first" ]; then
  if grep -q 'gh auth login' "$errf" 2>/dev/null; then fortkeep_result "$ID" NA "Not logged in to the GitHub CLI"
  else fortkeep_result "$ID" ERROR "GitHub gave no answer" "gh printed no response; check the network and try again"; fi
  exit 0
fi
# Only a real status line is trusted, and only its 3-digit code is ever echoed.
code="$(printf '%s\n' "$first" | sed -nE 's#^HTTP/[0-9.]+ ([0-9]{3})([^0-9].*)?$#\1#p')"
case "$code" in
  200) ;;
  401) fortkeep_result "$ID" NA "Not logged in to the GitHub CLI"; exit 0 ;;
  [0-9][0-9][0-9]) fortkeep_result "$ID" ERROR "GitHub answered with an unexpected status" "Status $code"; exit 0 ;;
  *) fortkeep_result "$ID" ERROR "GitHub gave an answer that could not be read" "The response did not start with a status line"; exit 0 ;;
esac
exp="$(printf '%s\n' "$h" | awk 'tolower($1) == "github-authentication-token-expiration:" { $1 = ""; sub(/^ /, ""); print; exit }')"
if [ -n "$exp" ]; then fortkeep_result "$ID" PASS "The GitHub token expires on $exp"
else fortkeep_result "$ID" FAIL "The GitHub token has no expiry date" "Use a fine-grained token with an expiry (see BL-SE-04)"; fi
