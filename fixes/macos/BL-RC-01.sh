#!/bin/bash -p
# Sets "task.allowAutomaticTasks": "off" in every settings file of VS Code, VS Code Insiders, Cursor, Windsurf and
# VSCodium (checks/lib/editors.sh). Usage: apply | undo
# The setting works without devward, so devward uninstall leaves it in place (fixes/lib/applied.sh):
# devward: stays after uninstall
. "$(dirname "$0")/../lib/fix.sh"
ID=BL-RC-01
EDITORS="VS Code, VS Code Insiders, Cursor, Windsurf and VSCodium"
fx_require_approval "$ID" "${1:-}"
. "$DEVWARD_REPO/checks/lib/editors.sh"
case "$1" in
  apply)
    manual="" changed=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ "$(devward_auto_tasks "$f")" = off ] && continue
      tmp="$(mktemp)"
      if [ ! -f "$f" ]; then
        printf '{\n  "task.allowAutomaticTasks": "off"\n}\n' > "$tmp"
      elif jq -e . "$f" >/dev/null 2>&1; then
        jq '. + {"task.allowAutomaticTasks": "off"}' "$f" > "$tmp" 2>/dev/null || : > "$tmp"
      else
        : > "$tmp"
      fi
      if [ ! -s "$tmp" ]; then
        rm -f "$tmp"; manual="$manual $(devward_tilde "$f")"; continue
      fi
      had=0; [ -f "$f" ] && { had=1; cp -p "$f" "$tmp.orig"; }
      if ! fx_backup "$ID" "$f"; then  # never write through a file that has no backup
        rm -f "$tmp" "$tmp.orig"; manual="$manual $(devward_tilde "$f")"; continue
      fi
      cat "$tmp" > "$f" 2>/dev/null
      if [ "$(devward_auto_tasks "$f")" = off ]; then
        changed=1
      else
        if [ "$had" -eq 1 ]; then cat "$tmp.orig" > "$f" 2>/dev/null; else rm -f "$f"; fi
        manual="$manual $(devward_tilde "$f")"
      fi
      rm -f "$tmp" "$tmp.orig"
    done <<EOT
$(devward_editor_settings)
EOT
    if [ "$changed" -eq 1 ]; then fx_seal "$ID"; fx_log "$ID" apply "automatic tasks set to off in $EDITORS"
    else rm -rf "${DEVWARD_BACKUPS:?}/$ID/$FX_STAMP"; fi
    if [ -n "$manual" ]; then
      echo "MANUAL: these settings files can't be edited safely by a script (comments, an unusual format, or a link to a missing file); open each with Cmd+Shift+P → \"Preferences: Open User Settings (JSON)\" and add \"task.allowAutomaticTasks\": \"off\", just after the opening {:$manual"
      exit 3
    fi
    if [ "$changed" -eq 0 ]; then echo "nothing to change: automatic tasks are already off in $EDITORS"; exit 0; fi
    echo "done: automatic tasks are off in $EDITORS" ;;
  undo)
    fx_restore "$ID"
    fx_log "$ID" undo "restored editor settings from backup"
    echo "restored" ;;
esac
