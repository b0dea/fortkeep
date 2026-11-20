load helpers

setup() {
  setup_env
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/apps.sh"; . "$REPO/checks/lib/browsers.sh"; . "$REPO/checks/lib/launchd.sh"
  AS="$HOME/Library/Application Support"
}
chrome_ext() {  # PROFILE ID NAME [LOCALE_KEY]
  local d="$1/Extensions/$2/1.0_0"; mkdir -p "$d"
  if [ -n "${4:-}" ]; then
    jq -n --arg k "__MSG_$4__" '{name:$k}' > "$d/manifest.json"
    mkdir -p "$d/_locales/en"; jq -n --arg k "$4" --arg n "$3" '{($k):{message:$n}}' > "$d/_locales/en/messages.json"
  else jq -n --arg n "$3" '{name:$n}' > "$d/manifest.json"; fi
}

@test "fortkeep_app finds apps in /Applications and ~/Applications" {
  mkdir -p "$FORTKEEP_SYSROOT/Applications/KnockKnock.app" "$HOME/Applications/LuLu.app"
  [ "$(fortkeep_app KnockKnock)" = "$FORTKEEP_SYSROOT/Applications/KnockKnock.app" ]
  [ "$(fortkeep_app Nope LuLu)" = "$HOME/Applications/LuLu.app" ]
  run fortkeep_app Nope; [ "$status" -eq 1 ]
}
@test "fortkeep_endpoint_products names protection apps and Defender's command once each, and ignores look-alikes" {
  FORTKEEP_USER_PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run fortkeep_endpoint_products; [ -z "$output" ]
  mkdir -p "$FORTKEEP_SYSROOT/Applications/Bitdefender Antivirus for Mac.app" "$FORTKEEP_SYSROOT/Applications/Microsoft Defender.app" \
    "$FORTKEEP_SYSROOT/Applications/Network Reset Tool.app" "$FORTKEEP_SYSROOT/Applications/SentinelOne/SentinelOne Extensions.app"
  stub mdatp 'exit 0'
  FORTKEEP_USER_PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run fortkeep_endpoint_products
  [ "${#lines[@]}" -eq 3 ]; [[ "$output" == *Bitdefender* ]]; [[ "$output" == *"Microsoft Defender"* ]]; [[ "$output" == *SentinelOne* ]]
  [[ "$output" != *Reset* ]]
}
@test "fortkeep_running asks pgrep for an exact name" {
  stub pgrep '[ "$1" = -x ] && [ "$2" = LuLu ]'
  fortkeep_running LuLu
  run fortkeep_running Other; [ "$status" -ne 0 ]
}
@test "Chromium profiles and extensions, with localised names" {
  P="$AS/Google/Chrome/Default"; mkdir -p "$P"; echo '{}' > "$P/Preferences"
  Q="$AS/BraveSoftware/Brave-Browser/Profile 1"; mkdir -p "$Q"; echo '{}' > "$Q/Preferences"
  mkdir -p "$AS/Microsoft Edge/Default"
  chrome_ext "$P" aeblfdkhhhdcdjpifhhbdiojplfjncoa "1Password" extName
  chrome_ext "$P" cjpalhdlnbpafiamejdnhcphjbkeiagm "uBlock Origin"
  mkdir -p "$P/Extensions/Temp"
  run fortkeep_chromium_profiles; [ "${#lines[@]}" -eq 2 ]; [[ "$output" == *"Chrome	$P"* ]]; [[ "$output" == *"Brave	$Q"* ]]
  run fortkeep_extensions Chrome "$P"; [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"aeblfdkhhhdcdjpifhhbdiojplfjncoa	1Password"* ]]; [[ "$output" == *"uBlock Origin"* ]]
}
@test "Firefox profiles from profiles.ini, relative and absolute, and their extensions" {
  F="$AS/Firefox"; mkdir -p "$F/Profiles/a.default" "$BATS_TEST_TMPDIR/abs"
  printf '[General]\nStartWithLastProfile=1\n\n[Profile0]\nName=a\nIsRelative=1\nPath=Profiles/a.default\n\n[Profile1]\nName=b\nPath=%s\nIsRelative=0\n\n[Profile2]\nName=gone\nIsRelative=1\nPath=Profiles/missing\n' "$BATS_TEST_TMPDIR/abs" > "$F/profiles.ini"
  jq -n '{addons:[{id:"uBlock0@raymondhill.net",type:"extension",location:"app-profile",defaultLocale:{name:"uBlock Origin"}},{id:"x@sys",type:"extension",location:"app-system-defaults",defaultLocale:{name:"System"}}]}' > "$F/Profiles/a.default/extensions.json"
  run fortkeep_firefox_profiles; [ "${#lines[@]}" -eq 2 ]
  run fortkeep_extensions Firefox "$F/Profiles/a.default"; [ "$output" = "uBlock0@raymondhill.net	uBlock Origin" ]
}
@test "user LaunchAgents: label, weekly schedule, script, loaded" {
  L="$HOME/Library/LaunchAgents"; mkdir -p "$L"
  plutil -create xml1 "$L/a.plist"; plutil -insert Label -string a.job "$L/a.plist"
  plutil -insert ProgramArguments -json '["/bin/zsh","/opt/x/weekly.sh"]' "$L/a.plist"
  plutil -insert StartCalendarInterval -json '{"Weekday":1,"Hour":9}' "$L/a.plist"
  plutil -create xml1 "$L/b.plist"; plutil -insert Label -string b.job "$L/b.plist"
  plutil -insert Program -string /usr/local/bin/b "$L/b.plist"
  plutil -insert StartCalendarInterval -json '[{"Hour":1},{"Weekday":3}]' "$L/b.plist"
  plutil -create xml1 "$L/c.plist"; plutil -insert Label -string c.job "$L/c.plist"; plutil -insert RunAtLoad -bool true "$L/c.plist"
  run fortkeep_user_agents; [ "${#lines[@]}" -eq 3 ]
  fortkeep_agent_weekly "$L/a.plist"; fortkeep_agent_weekly "$L/b.plist"
  run fortkeep_agent_weekly "$L/c.plist"; [ "$status" -ne 0 ]
  [ "$(fortkeep_agent_script "$L/a.plist")" = /opt/x/weekly.sh ]
  [ "$(fortkeep_agent_script "$L/b.plist")" = /usr/local/bin/b ]
  plutil -replace ProgramArguments -json '["/bin/zsh","-l","/opt/x/s.sh"]' "$L/a.plist"
  [ "$(fortkeep_agent_script "$L/a.plist")" = /opt/x/s.sh ]; [ -z "$(fortkeep_agent_command "$L/a.plist")" ]
  plutil -replace ProgramArguments -json '["/bin/zsh","-lc","brew update"]' "$L/a.plist"
  [ "$(fortkeep_agent_command "$L/a.plist")" = "brew update" ]; [ -z "$(fortkeep_agent_script "$L/a.plist")" ]
  stub launchctl '[ "$1" = print ] && [ "${2##*/}" = a.job ]'
  fortkeep_agent_loaded a.job
  run fortkeep_agent_loaded b.job; [ "$status" -ne 0 ]
}
