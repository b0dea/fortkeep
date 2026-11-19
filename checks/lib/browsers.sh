#!/bin/bash
# Browser profiles and extensions: Chromium family and Firefox. Safari is left out on purpose:
# its passwords live in the Keychain, and reading its settings needs Full Disk Access.
DEVWARD_CHROMIUM='Google/Chrome|Chrome
Google/Chrome Beta|Chrome Beta
Google/Chrome Dev|Chrome Dev
Google/Chrome Canary|Chrome Canary
BraveSoftware/Brave-Browser|Brave
BraveSoftware/Brave-Browser-Beta|Brave Beta
BraveSoftware/Brave-Browser-Nightly|Brave Nightly
Microsoft Edge|Edge
Microsoft Edge Beta|Edge Beta
Microsoft Edge Dev|Edge Dev
Microsoft Edge Canary|Edge Canary
Arc/User Data|Arc
Chromium|Chromium
Vivaldi|Vivaldi'

devward_chromium_profiles() {  # Browser<TAB>profile dir, for each profile with a Preferences file that isn't private
  # With an argument, prints "!skipped" for each private browser or profile folder instead.
  local base name d p
  while IFS='|' read -r base name; do
    d="$HOME/Library/Application Support/$base"
    [ -d "$d" ] || continue
    if devward_is_private "$d"; then [ -z "${1:-}" ] || echo '!skipped'; continue; fi  # never listed
    for p in "$d/Default" "$d"/Profile\ *; do
      if devward_is_private "$p"; then [ -z "${1:-}" ] || echo '!skipped'; continue; fi
      [ -z "${1:-}" ] && [ -f "$p/Preferences" ] && printf '%s\t%s\n' "$name" "$p"
    done
  done <<EOF
$DEVWARD_CHROMIUM
EOF
  return 0
}

devward_firefox_dirs() {  # the folder of each profiles.ini entry, whether it exists or not
  local base="$HOME/Library/Application Support/Firefox" rel p
  [ -f "$base/profiles.ini" ] || return 0
  awk -F= '
    /^\[/ { if (p != "") print r "\t" p; p = ""; r = 1; next }
    /^IsRelative=/ { r = $2 } /^Path=/ { p = substr($0, 6) }
    END { if (p != "") print r "\t" p }' "$base/profiles.ini" \
  | while IFS="$(printf '\t')" read -r rel p; do
      if [ "$rel" = 0 ]; then printf '%s\n' "$p"; else printf '%s\n' "$base/$p"; fi
    done
}

devward_firefox_profiles() {  # Firefox<TAB>profile dir, for each existing profile folder that isn't private
  local d
  devward_firefox_dirs | while IFS= read -r d; do
    devward_is_private "$d" && continue
    [ -d "$d" ] && printf 'Firefox\t%s\n' "$d"
  done
}

devward_profiles_note() {  # prints " (a private folder was excluded)" when a profile was skipped as private
  local d
  { devward_chromium_profiles skipped; devward_firefox_dirs | while IFS= read -r d; do devward_is_private "$d" && echo '!skipped'; done; } \
    | grep -qx '!skipped' && printf ' (a private folder was excluded)'
  return 0
}

devward_profiles() { devward_chromium_profiles; devward_firefox_profiles; }

devward_extensions() {  # BROWSER PROFILE_DIR — id<TAB>name of each installed extension
  local e id v m n k d
  if [ "$1" = Firefox ]; then
    jq -r '.addons // [] | .[] | select(.type == "extension" and .location == "app-profile")
      | "\(.id)\t\(.defaultLocale.name // .id)"' "$2/extensions.json" 2>/dev/null
    return 0
  fi
  for e in "$2/Extensions"/*/; do
    id="$(basename "$e")"
    printf '%s' "$id" | grep -Eq '^[a-p]{32}$' || continue
    v=""; for d in "$e"*/; do [ -d "$d" ] && v="$d"; done; m="$v/manifest.json"
    n="$(jq -r '.name // ""' "$m" 2>/dev/null)"
    case "$n" in
      __MSG_*__)
        k="${n#__MSG_}"; k="${k%__}"
        n="$(cat "$v/_locales/en/messages.json" "$v/_locales/en_US/messages.json" 2>/dev/null \
          | jq -rs --arg k "$k" '[.[] | to_entries[] | select(.key | ascii_downcase == ($k | ascii_downcase)) | .value.message] | first // ""')" ;;
    esac
    printf '%s\t%s\n' "$id" "${n:-$id}"
  done
}

devward_enabled_extensions() {  # BROWSER PROFILE_DIR — devward_extensions without the ones turned off
  local off="" f
  if [ "$1" = Firefox ]; then
    off="$(jq -r '.addons // [] | .[] | select(.userDisabled == true or .active == false) | .id' "$2/extensions.json" 2>/dev/null)"
  else
    # Chrome keeps each extension's state in Secure Preferences (older versions: Preferences): a non-empty
    # disable_reasons, a list now and a bit mask before, means it is turned off.
    for f in "$2/Preferences" "$2/Secure Preferences"; do
      [ -f "$f" ] && off="$off"$'\n'"$(jq -r '.extensions.settings // {} | objects | to_entries[]
        | select(.value | objects | .disable_reasons | (type == "array" and length > 0) or (type == "number" and . != 0)) | .key' "$f" 2>/dev/null)"
    done
  fi
  devward_extensions "$1" "$2" | OFF="$off" awk -F '\t' 'BEGIN { n = split(ENVIRON["OFF"], a, "\n"); for (i = 1; i <= n; i++) skip[a[i]] = 1 } !($1 in skip)'
}

devward_extensions_readable() {  # BROWSER PROFILE_DIR — fails when the extension list exists but cannot be read
  if [ "$1" = Firefox ]; then
    [ ! -e "$2/extensions.json" ] || jq -e . "$2/extensions.json" >/dev/null 2>&1
  else
    [ ! -e "$2/Extensions" ] || { [ -d "$2/Extensions" ] && [ -r "$2/Extensions" ] && [ -x "$2/Extensions" ]; }
  fi
}
