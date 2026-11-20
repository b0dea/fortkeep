#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/browsers.sh"
ID=BL-BR-01
profiles="$(fortkeep_profiles)"; pn="$(fortkeep_profiles_note)"
[ -n "$profiles" ] || { fortkeep_result "$ID" NA "No Chrome-family or Firefox profiles (Safari keeps passwords in the Keychain)" "${pn# }"; exit 0; }
command -v jq >/dev/null 2>&1 || { fortkeep_result "$ID" ERROR "Couldn't read browser settings" "jq is not available$pn"; exit 0; }
cant() { unread="$unread, $1 ($(basename "$2"))"; }  # BROWSER PROFILE — noted; the caller skips the profile
policy_off() {  # BROWSER — 0 when a managed policy turns it off, 1 when not, 2 when the policy file is unreadable
  local b f v
  case "$1" in Chrome) b=com.google.Chrome ;; Brave) b=com.brave.Browser ;; Edge) b=com.microsoft.Edge ;;
    Arc) b=company.thebrowser.Browser ;; Chromium) b=org.chromium.Chromium ;; Vivaldi) b=com.vivaldi.Vivaldi ;; *) return 1 ;; esac
  f="$(fortkeep_path "/Library/Managed Preferences/$b.plist")"
  [ -e "$f" ] || return 1
  plutil -lint "$f" >/dev/null 2>&1 || return 2
  v="$(plutil -extract PasswordManagerEnabled raw "$f" 2>/dev/null)"
  [ "$v" = false ]
}
saved() {  # BROWSER PROFILE — prints how many passwords the profile still holds (a count; values are never read); 1 = can't tell
  local f c n=0
  if [ "$1" = Firefox ]; then
    [ -e "$2/logins.json" ] || { echo 0; return 0; }
    jq -er '.logins // [] | length' "$2/logins.json" 2>/dev/null; return
  fi
  for f in "$2/Login Data" "$2/Login Data For Account"; do
    [ -e "$f" ] || continue
    # immutable=1: the browser keeps the file open and locked; the read takes no lock and writes nothing.
    c="$(sqlite3 "file:$(printf '%s' "$f" | perl -pe 's/([^A-Za-z0-9\/._~-])/sprintf("%%%02X", ord $1)/ge')?immutable=1" \
      'select count(*) from logins where blacklisted_by_user = 0' 2>/dev/null)" || return 1
    case "$c" in ''|*[!0-9]*) return 1 ;; esac
    n=$((n + c))
  done
  echo "$n"
}
total=0; on=""; unread=""; kept=""
while IFS="$(printf '\t')" read -r b p; do
  [ -n "$b" ] || continue
  total=$((total + 1))
  n="$(saved "$b" "$p")" || { cant "$b" "$p"; continue; }
  [ "$n" -eq 0 ] || kept="$kept, $b ($(basename "$p")): $n"
  if [ "$b" = Firefox ]; then
    off=0
    for f in prefs.js user.js; do
      [ -e "$p/$f" ] || continue
      grep -Eq 'user_pref\("signon\.rememberSignons",[[:space:]]*false\)' "$p/$f" 2>/dev/null
      case $? in 0) off=1 ;; 1) ;; *) cant "$b" "$p"; continue 2 ;; esac
    done
    [ "$off" -eq 1 ] && continue
  else
    policy_off "$b"
    case $? in 0) continue ;; 1) ;; *) cant "$b" "$p"; continue ;; esac
    v="$(jq -r '(.credentials_enable_service == false) or (.profile.password_manager_enabled == false)' "$p/Preferences" 2>/dev/null)" || { cant "$b" "$p"; continue; }
    case "$v" in true) continue ;; false) ;; *) cant "$b" "$p"; continue ;; esac
  fi
  on="$on, $b ($(basename "$p"))"
done <<EOF2
$profiles
EOF2
left="${kept:+. Passwords still saved (turning the manager off does not delete them): ${kept#, }; move them to your password manager, then delete them in the browser}"
if [ -n "$on" ]; then fortkeep_result "$ID" FAIL "Built-in password manager on in some browser profiles" "On (the browser's default counts as on) in: ${on#, }$left${unread:+. Could not read: ${unread#, }}$pn"
elif [ -n "$kept" ]; then fortkeep_result "$ID" FAIL "Built-in password manager off, but passwords are still saved in some browser profiles" "${left#. }${unread:+. Could not read: ${unread#, }}$pn"
elif [ -n "$unread" ]; then fortkeep_result "$ID" ERROR "Couldn't read the settings of ${unread#, }" "The settings file is unreadable or damaged$pn"
else fortkeep_result "$ID" PASS "Built-in password manager off in all $total browser profiles" "${pn# }"; fi
