#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=OV-TP-01
snip='for v in NODE_EXTRA_CA_CERTS SSL_CERT_FILE REQUESTS_CA_BUNDLE; do p="$(printenv "$v")"; if [ -n "$p" ] && [ -r "$p" ] && grep -q "BEGIN CERTIFICATE" "$p"; then echo "$v ok"; else echo "$v missing"; fi; done'
bad=""; unknown=""; silent=""
for t in zsh zsh-login clean-zsh-login; do
  out="$(fortkeep_shell_probe "$t" "$snip")"; rc=$?
  if [ "$rc" -eq 142 ]; then unknown="$unknown, $(fortkeep_shell_label "$t")"; continue; fi
  if [ "$rc" -ne 0 ] || [ "$(printf '%s\n' "$out" | awk '$2 == "ok" || $2 == "missing"' | wc -l | tr -d ' ')" -ne 3 ]; then
    silent="$silent, $(fortkeep_shell_label "$t")"; continue
  fi
  m="$(printf '%s\n' "$out" | awk '$2 == "missing" { print $1 }' | paste -sd, - | sed 's/,/, /g')"
  [ -n "$m" ] && bad="$bad; $(fortkeep_shell_label "$t"): $m"
done
if [ -n "$bad" ]; then fortkeep_result "$ID" FAIL "The CA bundle isn't set for every non-interactive shell" "Missing or not a CA bundle in ${bad#; }${unknown:+. Timed out: ${unknown#, }}${silent:+. No answer from: ${silent#, }}"
elif [ -n "$unknown" ]; then fortkeep_result "$ID" ERROR "Timed out: ${unknown#, }" "A start-up file may be slow or waiting for input"
elif [ -n "$silent" ]; then fortkeep_result "$ID" ERROR "No answer from: ${silent#, }" "The shell ended before the check could finish"
else fortkeep_result "$ID" PASS "NODE_EXTRA_CA_CERTS, SSL_CERT_FILE and REQUESTS_CA_BUNDLE point to a CA bundle in zsh -c, zsh -lc and env -i zsh -lc"; fi
