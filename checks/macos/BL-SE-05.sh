#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SE-05
aws="$HOME/.aws/credentials"; gc="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"
if [ ! -f "$aws" ] && [ ! -d "$gc" ]; then fortkeep_result "$ID" NA "No AWS or Google Cloud credentials files"; exit 0; fi
long=0; temp=0; sa=0; bad=""
if [ -f "$aws" ]; then
  long="$(grep -Ec '^[[:space:]]*aws_access_key_id[[:space:]]*=[[:space:]]*AKIA' "$aws" 2>/dev/null)"; r1=$?
  temp="$(grep -Ec '^[[:space:]]*aws_access_key_id[[:space:]]*=[[:space:]]*ASIA' "$aws" 2>/dev/null)"; r2=$?
  if [ ! -r "$aws" ] || [ "$r1" -gt 1 ] || [ "$r2" -gt 1 ]; then bad="$(fortkeep_tilde "$aws")"; long=0; temp=0; fi
fi
for f in "$gc/application_default_credentials.json" "$gc"/legacy_credentials/*/adc.json; do
  [ -f "$f" ] && [ ! -r "$f" ] && { bad="$bad $(fortkeep_tilde "$f")"; continue; }
  [ -f "$f" ] && [ "$(jq -r '.type // ""' "$f" 2>/dev/null)" = service_account ] && sa=$((sa + 1))
done
[ -n "$bad" ] && [ "$long" -eq 0 ] && [ "$sa" -eq 0 ] && { fortkeep_result "$ID" ERROR "Could not read${bad:+ }$bad" "Check the file permissions"; exit 0; }
if [ "$long" -gt 0 ] || [ "$sa" -gt 0 ]; then
  fortkeep_result "$ID" FAIL "$long long-lived AWS key(s), $sa Google service-account key file(s)" "Use SSO sessions (aws sso login, gcloud auth login) instead"
else
  fortkeep_result "$ID" PASS "No long-lived cloud keys ($temp short-lived AWS session(s))"
fi
