#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SE-04
gh="$(fortkeep_real_cmd gh)" || { fortkeep_result "$ID" NA "GitHub CLI is not installed"; exit 0; }
# The token stays in this variable for one case statement and is never printed.
tok="$(fortkeep_timeout "${FORTKEEP_GH_TIMEOUT:-10}" "$gh" auth token 2>/dev/null </dev/null)"; rc=$?
[ "$rc" -eq 142 ] && { fortkeep_result "$ID" ERROR "gh did not answer in time" "gh auth token took too long; try again"; exit 0; }
case "$tok" in
  '') if [ "$rc" -eq 0 ]; then kind=empty; else kind=none; fi ;;
  github_pat_*) kind=fine ;;
  ghu_*) kind=app ;;
  gho_*) kind="an OAuth token from gh auth login (classic, full repo access)" ;;
  ghp_*) kind="a classic personal access token" ;;
  *) kind=unknown ;;
esac
tok=""
plain=""
f="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml"
[ -f "$f" ] && grep -Eq '^[[:space:]]*oauth_token:' "$f" && plain="The token is stored in a plain file ($(fortkeep_tilde "$f")), readable by any program running as you."
case "$kind" in
  empty) fortkeep_result "$ID" ERROR "gh returned no token" "gh auth token succeeded but printed nothing" ;;
  none) fortkeep_result "$ID" NA "Not logged in to the GitHub CLI" ;;
  unknown) fortkeep_result "$ID" ERROR "gh token kind unknown" "Could not tell what kind of token gh uses" ;;
  fine|app)
    if [ -n "$plain" ]; then fortkeep_result "$ID" FAIL "gh uses a fine-grained token" "$plain"
    else fortkeep_result "$ID" PASS "gh uses a fine-grained token, kept in the Keychain"; fi ;;
  *) fortkeep_result "$ID" FAIL "gh uses $kind" "Switch to a fine-grained token with an expiry. $plain" ;;
esac
