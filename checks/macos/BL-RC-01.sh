#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/editors.sh"
ID=BL-RC-01
total=0; good=0; bad=""; unreadable=""; priv=""
devward_editor_private_skipped && priv=" (a private folder was excluded)"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  total=$((total + 1))
  case "$(devward_auto_tasks "$f")" in
    off) good=$((good + 1)) ;;
    error) unreadable="$unreadable $(devward_tilde "$f")" ;;
    *) bad="$bad $(devward_tilde "$f")" ;;
  esac
done <<EOF2
$(devward_editor_settings)
EOF2
if [ $total -eq 0 ] && [ -n "$priv" ]; then devward_result "$ID" ERROR "Could not check the editor settings" "a private folder was excluded"; exit 0; fi
if [ $total -eq 0 ]; then devward_result "$ID" NA "No VS Code, Cursor, Windsurf or VSCodium installed"; exit 0; fi
ev="$good of $total settings files set automatic tasks to off"
# The baseline says "set": an editor default of off doesn't count, since a later version can change it.
if [ -n "$bad" ]; then devward_result "$ID" FAIL "$ev" "Not set to off in:$bad (the editor's default doesn't count)${unreadable:+. Could not read:$unreadable}$priv"
elif [ -n "$unreadable" ]; then devward_result "$ID" ERROR "$ev" "Could not read:$unreadable$priv"
else devward_result "$ID" PASS "$ev" "${priv# }"; fi
