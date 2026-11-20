#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SE-05
aws="$HOME/.aws/credentials"; gc="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"
# A credentials file or folder inside a private folder is never opened, listed or named.
skipped=""
pub() { ! fortkeep_is_private "$1" || { skipped=1; return 1; }; }  # PATH — outside every private folder
pub "$aws" || aws=""
pub "$gc" || gc=""
if [ ! -f "$aws" ] && [ ! -d "$gc" ]; then
  if [ -n "$skipped" ]; then fortkeep_result "$ID" ERROR "Could not check the cloud credentials files" "a private folder was excluded"
  else fortkeep_result "$ID" NA "No AWS or Google Cloud credentials files"; fi
  exit 0
fi
long=0; temp=0; sa=0; bad=""
if [ -f "$aws" ]; then
  long="$(grep -Ec '^[[:space:]]*aws_access_key_id[[:space:]]*=[[:space:]]*AKIA' "$aws" 2>/dev/null)"; r1=$?
  temp="$(grep -Ec '^[[:space:]]*aws_access_key_id[[:space:]]*=[[:space:]]*ASIA' "$aws" 2>/dev/null)"; r2=$?
  if [ ! -r "$aws" ] || [ "$r1" -gt 1 ] || [ "$r2" -gt 1 ]; then bad="$(fortkeep_tilde "$aws")"; long=0; temp=0; fi
fi
gfiles=()
if [ -d "$gc" ]; then
  gfiles=("$gc/application_default_credentials.json")
  if pub "$gc/legacy_credentials"; then gfiles+=("$gc"/legacy_credentials/*/adc.json); fi
fi
for f in "${gfiles[@]}"; do
  pub "$f" || continue
  [ -f "$f" ] && [ ! -r "$f" ] && { bad="$bad $(fortkeep_tilde "$f")"; continue; }
  [ -f "$f" ] && [ "$(jq -r '.type // ""' "$f" 2>/dev/null)" = service_account ] && sa=$((sa + 1))
done
ex=""; [ -z "$skipped" ] || ex="; a private folder was excluded"
[ -n "$bad" ] && [ "$long" -eq 0 ] && [ "$sa" -eq 0 ] && { fortkeep_result "$ID" ERROR "Could not read${bad:+ }$bad" "Check the file permissions$ex"; exit 0; }
if [ "$long" -gt 0 ] || [ "$sa" -gt 0 ]; then
  fortkeep_result "$ID" FAIL "$long long-lived AWS key(s), $sa Google service-account key file(s)" "Use SSO sessions (aws sso login, gcloud auth login) instead$ex"
elif [ -n "$skipped" ]; then
  fortkeep_result "$ID" ERROR "Could not check every cloud credentials file" "a private folder was excluded"
else
  fortkeep_result "$ID" PASS "No long-lived cloud keys ($temp short-lived AWS session(s))"
fi
