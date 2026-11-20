#!/bin/bash
# Installed apps and running processes.
fortkeep_app() {  # NAME... — path of the first NAME.app found in /Applications or ~/Applications
  local n d
  for n in "$@"; do
    for d in "$(fortkeep_path /Applications)" "$HOME/Applications"; do
      [ -d "$d/$n.app" ] && { printf '%s\n' "$d/$n.app"; return 0; }
    done
  done
  return 1
}

fortkeep_running() { pgrep -x "$1" >/dev/null 2>&1; }  # NAME — a process with exactly this name runs

# Endpoint protection and antivirus products, matched by app name (Defender also by its command).
FORTKEEP_ENDPOINT_RE='(^|[^a-z])(defender|falcon|crowdstrike|sentinelone|bitdefender|endpoint security|eset|sophos|jamf ?protect|malwarebytes|trend ?micro|kaspersky|norton|avast|avg|intego|clamxav|webroot|cortex xdr|carbon ?black|cylance|withsecure|f-secure)([^a-z]|$)'
fortkeep_endpoint_products() {  # product names found, one per line, each once
  local a n
  {
    { fortkeep_real_cmd mdatp >/dev/null || [ -x "$(fortkeep_path /usr/local/bin/mdatp)" ]; } && echo "Microsoft Defender"
    for a in "$(fortkeep_path /Applications)"/*.app "$(fortkeep_path /Applications)"/*/*.app; do
      [ -d "$a" ] || continue
      n="$(basename "$a" .app)"
      printf '%s\n' "$n" | grep -Eiq "$FORTKEEP_ENDPOINT_RE" && printf '%s\n' "$n"
    done
  } | awk '!s[$0]++'
}

fortkeep_endpoint_running() {  # names of endpoint products whose system extension is activated and enabled; 3 = can't read
  local out
  out="$(systemextensionsctl list 2>/dev/null)" || return 3
  printf '%s\n' "$out" | grep -Eq '^[0-9]+ extension\(s\)' || return 3
  # Lines are enabled, active, team, "bundle (version)", name, [state], tab separated; the match reads bundle and name.
  printf '%s\n' "$out" | awk -F '\t' -v re="$FORTKEEP_ENDPOINT_RE" '$NF == "[activated enabled]" && NF >= 6 {
    b = $(NF - 2); sub(/ .*/, "", b)
    if (tolower(b " " $(NF - 1)) ~ re && !seen[$(NF - 1)]++) print $(NF - 1) }'
}

fortkeep_mdatp_field() {  # FIELD — one `mdatp health` value, quotes removed; 142 = timed out, 1 = no mdatp, 3 = mdatp failed
  local m v rc
  m="$(fortkeep_real_cmd mdatp)" || m="$(fortkeep_path /usr/local/bin/mdatp)"
  [ -x "$m" ] || return 1
  v="$(fortkeep_timeout "${FORTKEEP_MDATP_TIMEOUT:-15}" "$m" health --field "$1" 2>/dev/null </dev/null)"; rc=$?
  [ "$rc" -eq 142 ] && return 142
  [ "$rc" -eq 0 ] || return 3
  printf '%s\n' "$v" | head -1 | tr -d '"' | sed 's/^ *//; s/ *$//'
}
