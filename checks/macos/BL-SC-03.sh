#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-SC-03
SHIMS="$HOME/.safe-chain/shims"
STD=/usr/bin:/bin:/usr/sbin:/sbin
CONF="$(fortkeep_path /private/var/db/com.apple.xpc.launchd/config/user.plist)"
# What your running apps got: only the PATH word of each one's environment is read, inside the
# pipeline; no other variable is kept. Apps whose PATH is neither shims-first nor launchd's are left out.
me="$(id -u)"; good=""; bad=""; shown=""; ng=0; nb=0; listed=1
list="$(ps -axo pid=,ppid=,uid=,comm= 2>/dev/null)" && [ -n "$list" ] || listed=0
while read -r pid ppid uid comm; do
  [ "$ppid" = 1 ] && [ "$uid" = "$me" ] || continue
  case "$comm" in *.app/Contents/MacOS/*) ;; *) continue ;; esac
  p="$(ps -Eww -o command= -p "$pid" 2>/dev/null | tr ' ' '\n' | grep '^PATH=' | tail -n 1)"
  name="$(basename "$comm")"
  case "${p#PATH=}" in
    "$SHIMS":*|"$SHIMS") case "$good," in *", $name,"*) ;; *) ng=$((ng + 1)); good="$good, $name" ;; esac ;;
    "$STD") case "$bad," in *", $name,"*) ;; *) nb=$((nb + 1)); bad="$bad, $name"; [ "$nb" -le 5 ] && shown="$shown, $name" ;; esac ;;
  esac
done <<EOF
$list
EOF
# launchd's stored user PATH (set by the admin command) and whether a restart has applied it.
conf=none
if [ -e "$CONF" ]; then
  if j="$(plutil -convert json -o - "$CONF" 2>/dev/null)"; then
    jq -e --arg s "$SHIMS" '[.. | strings | select(. == $s or startswith($s + ":"))] | length > 0' >/dev/null 2>&1 <<<"$j"
    case $? in
      0) boot="$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*{ sec = \([0-9][0-9]*\),.*/\1/p')"
         mt="$(stat -f %m "$CONF" 2>/dev/null)"
         case "$boot:$mt" in
           *[!0-9:]*|:*|*:) conf=noboot ;;
           *) if [ "$mt" -lt "$boot" ]; then conf=active; else conf=pending; fi ;;
         esac ;;
      1) conf=other ;;
      *) conf=unreadable ;;
    esac
  else conf=unreadable; fi
else
  # Absent, or hidden by a folder on the way that can't be searched: the deepest folder that exists decides.
  d="$(dirname "$CONF")"; while [ ! -e "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do d="$(dirname "$d")"; done
  [ -d "$d" ] && [ ! -x "$d" ] && conf=unreadable
fi
unlisted=""; [ "$listed" -eq 0 ] && unlisted=" The running apps couldn't be listed."
# Login items start as their own launchd jobs and can miss the setting, and nothing tells them apart
# from apps the person opened: the setting decides, and apps without the shims are only named.
apps=""
if [ "$nb" -gt 0 ]; then
  more=""; [ "$nb" -gt 5 ] && more=" and $((nb - 5)) more"
  apps=" Without the shims: ${shown#, }$more."
  [ "$conf" = active ] && apps="$apps These are usually login items: quit one and reopen it from the Dock or Finder, and it has the shims until it next starts at login."
fi
trim() { printf '%s' "${1# }"; }
case "$conf" in
  active)
    if [ "$ng" -gt 0 ]; then
      fortkeep_result "$ID" PASS "launchd's user PATH starts with the Safe Chain shims, and $ng of $((ng + nb)) running apps that show their PATH have them" "$(trim "$apps")"
    elif [ "$nb" -gt 0 ]; then
      fortkeep_result "$ID" FAIL "launchd's user PATH starts with the Safe Chain shims, but no running app has them: the setting isn't taking effect" "$(trim "$apps")"
    elif [ "$listed" -eq 1 ]; then
      fortkeep_result "$ID" PASS "launchd's user PATH starts with the Safe Chain shims (set before the last restart); no running app showed its PATH to confirm" ""
    else
      fortkeep_result "$ID" ERROR "launchd's user PATH starts with the Safe Chain shims, but the running apps couldn't be listed to confirm" "Run the check again."
    fi ;;
  pending) fortkeep_result "$ID" FAIL "launchd's user PATH starts with the Safe Chain shims, but only after a restart" "Restart the Mac to apply it.$apps$unlisted" ;;
  unreadable) fortkeep_result "$ID" ERROR "Couldn't read launchd's user config, which decides this control" "Run the check again.$unlisted" ;;
  noboot) fortkeep_result "$ID" ERROR "launchd's user PATH starts with the Safe Chain shims, but couldn't tell whether it was set before the last restart" "The Mac's boot time or the config's time couldn't be read.$unlisted" ;;
  *) fortkeep_result "$ID" FAIL "launchd's user PATH doesn't start with the Safe Chain shims" "$(trim "$apps Set launchd's user PATH with the admin command in the lesson, then restart.$unlisted")" ;;
esac
