#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-09
found=""
for a in TeamViewer AnyDesk RustDesk; do
  [ -d "$(fortkeep_path /Applications)/$a.app" ] && found="$found $a.app"
done
for d in /Library/PrivilegedHelperTools /Library/LaunchDaemons /Library/LaunchAgents /Library/Security/SecurityAgentPlugins; do
  for f in "$(fortkeep_path "$d")"/*; do
    [ -e "$f" ] || continue
    n="$(basename "$f")"
    case "$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')" in
      *teamviewer*|*anydesk*|*rustdesk*) found="$found $n" ;;
    esac
  done
done
if [ -z "$found" ]; then fortkeep_result "$ID" PASS "No TeamViewer, AnyDesk or RustDesk apps or helpers"
else fortkeep_result "$ID" FAIL "Found:$found" "If you don't actively use it, remove it with the vendor's own uninstaller"; fi
