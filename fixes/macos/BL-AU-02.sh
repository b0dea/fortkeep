#!/bin/bash -p
# Installs the weekly security check: a LaunchAgent that runs checks/weekly.sh (via its named launcher)
# every Wednesday at 10:00 and logs to ~/Library/Logs/fortkeep-weekly.log. Usage: apply | undo
. "$(dirname "$0")/../lib/fix.sh"
ID=BL-AU-02
fx_require_approval "$ID" "${1:-}"
LABEL=io.github.b0dea.fortkeep.weekly
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
LOG="$HOME/Library/Logs/fortkeep-weekly.log"
BK="$FORTKEEP_BACKUPS/$ID/$FX_STAMP"
stop() {  # MESSAGE — finish as MANUAL
  echo "MANUAL: $1"; exit 3
}
case "$1" in
  apply)
    # The job must also see this session's Claude config folder; a missing key matches an unset one.
    cur="$(plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw "$PLIST" 2>/dev/null)" || cur=""
    if [ -f "$PLIST" ] && launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 &&
       [ "$(plutil -extract ProgramArguments.0 raw "$PLIST" 2>/dev/null)" = "$FORTKEEP_REPO/checks/fortkeep-weekly" ] &&
       ! plutil -extract ProgramArguments.1 raw "$PLIST" >/dev/null 2>&1 &&
       [ "$cur" = "${CLAUDE_CONFIG_DIR:-}" ]; then
      echo "nothing to change: the weekly security check is installed and loaded"; exit 0
    fi
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" || stop "could not create ~/Library/LaunchAgents; nothing was changed"
    fx_backup "$ID" "$PLIST" || { rm -rf "$BK"; stop "could not back up $(fortkeep_tilde "$PLIST"); nothing was changed"; }
    env='{}'; [ -n "${CLAUDE_CONFIG_DIR:-}" ] && env="$(jq -cn --arg d "$CLAUDE_CONFIG_DIR" '{CLAUDE_CONFIG_DIR: $d}')"
    rm -f "$PLIST"
    if ! { plutil -create xml1 "$PLIST" && plutil -insert Label -string "$LABEL" "$PLIST" &&
           plutil -insert ProgramArguments -json "$(jq -cn --arg s "$FORTKEEP_REPO/checks/fortkeep-weekly" '[$s]')" "$PLIST" &&
           plutil -insert StartCalendarInterval -json '{"Weekday":3,"Hour":10,"Minute":0}' "$PLIST" &&
           plutil -insert StandardOutPath -string "$LOG" "$PLIST" && plutil -insert StandardErrorPath -string "$LOG" "$PLIST" &&
           plutil -insert EnvironmentVariables -json "$env" "$PLIST"; } >/dev/null 2>&1; then
      if fx_restore_file "$BK" "$PLIST"; then rm -rf "$BK"; stop "could not write the LaunchAgent; your previous setup was put back, nothing was changed"; fi
      stop "could not write the LaunchAgent, and the previous file could not be put back; backup kept in $(fortkeep_tilde "$BK")"
    fi
    fx_seal "$ID"
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
    launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || {
      fx_log "$ID" apply "weekly security check written but not loaded"
      stop "the job is written but didn't load; log out and back in, then re-check"
    }
    fx_log "$ID" apply "weekly security check installed (Wednesdays 10:00)"
    echo "done: the weekly security check runs every Wednesday at 10:00" ;;
  undo)
    # The LaunchAgent is wholly the fix's own, so undo removes it only if it is unchanged since apply.
    dir="$(fx_latest_backup "$ID")" || { echo "nothing to undo for $ID" >&2; exit 5; }
    fx_check_seal "$dir"  # before bootout, so a stopped undo leaves the job running
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
    fx_restore "$ID"
    fx_log "$ID" undo "removed the weekly security check"
    echo "restored" ;;
esac
