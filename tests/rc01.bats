load helpers

setup() { setup_env; }
U="Library/Application Support/Code/User"
chk() { run /bin/bash "$REPO/checks/macos/BL-RC-01.sh"; }

@test "no editor → NA" {
  chk; [ "$(field status)" = NA ]
}
@test "main settings off → PASS" {
  mkdir -p "$HOME/$U"; echo '{"task.allowAutomaticTasks":"off"}' > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "1 of 1 settings files set automatic tasks to off" ]
}
@test "profile without the setting → FAIL" {
  mkdir -p "$HOME/$U/profiles/abc"
  echo '{"task.allowAutomaticTasks":"off"}' > "$HOME/$U/settings.json"
  echo '{}' > "$HOME/$U/profiles/abc/settings.json"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 of 2 settings files set automatic tasks to off" ]
}
@test "a private editor folder or profile is never read or listed, and the result says one was excluded" {
  mkdir -p "$HOME/$U/profiles/secret"; echo '{"task.allowAutomaticTasks":"off"}' > "$HOME/$U/settings.json"
  echo '{}' > "$HOME/$U/profiles/secret/settings.json"
  echo "~/$U/profiles/secret" > "$DEVWARD_PRIVATE_PATHS"
  chk; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]; [[ "$output" != *secret* ]]
  echo "~/$U" > "$DEVWARD_PRIVATE_PATHS"
  chk; [ "$(field status)" = ERROR ]; [ "$(field note)" = "a private folder was excluded" ]
  echo "~/$U/profiles" > "$DEVWARD_PRIVATE_PATHS"
  chk; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]; [[ "$output" != *secret* ]]
}
@test "Windsurf, VSCodium and VS Code Insiders count too" {
  for app in Windsurf VSCodium "Code - Insiders"; do mkdir -p "$HOME/Library/Application Support/$app/User"; done
  echo '{"task.allowAutomaticTasks":"off"}' > "$HOME/Library/Application Support/Windsurf/User/settings.json"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 of 3 settings files set automatic tasks to off" ]
  [[ "$(field note)" == *VSCodium* ]]; [[ "$(field note)" == *Insiders* ]]
}
@test "editor installed but no settings file → FAIL" {
  mkdir -p "$HOME/$U"
  chk; [ "$(field status)" = FAIL ]
}
@test "JSON with comments is read with the fallback" {
  mkdir -p "$HOME/$U"
  printf '{\n  // keep\n  "task.allowAutomaticTasks": "off",\n}\n' > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = PASS ]
}
@test "Cursor counted too" {
  mkdir -p "$HOME/$U" "$HOME/Library/Application Support/Cursor/User"
  echo '{"task.allowAutomaticTasks":"off"}' > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 of 2 settings files set automatic tasks to off" ]
}

@test "commented-out key → FAIL" {
  mkdir -p "$HOME/$U"
  printf '{\n  // "task.allowAutomaticTasks": "off",\n}\n' > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "0 of 1 settings files set automatic tasks to off" ]
}
@test "block-commented key → FAIL" {
  mkdir -p "$HOME/$U"
  echo '{ /* "task.allowAutomaticTasks": "off" */ }' > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = FAIL ]
}
@test "nested key is not the top-level setting → FAIL" {
  mkdir -p "$HOME/$U"
  echo '{"x":{"task.allowAutomaticTasks":"off"}}' > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = FAIL ]
}
@test "// inside a string does not hide the real key → PASS" {
  mkdir -p "$HOME/$U"
  echo '{"url":"https://example.com/a","task.allowAutomaticTasks":"off"}' > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = PASS ]
}
@test "unreadable settings file → ERROR, one JSON line, no stderr" {
  mkdir -p "$HOME/$U"
  echo '{"task.allowAutomaticTasks":"off"}' > "$HOME/$U/settings.json"
  chmod 000 "$HOME/$U/settings.json"
  chk
  chmod 600 "$HOME/$U/settings.json"
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 1 ]
  jq -e . <<<"$output" >/dev/null
  [ "$(field status)" = ERROR ]
  [[ "$(field note)" == "Could not read: ~/"* ]]
}
@test "empty settings file → FAIL (unset)" {
  mkdir -p "$HOME/$U"
  : > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "0 of 1 settings files set automatic tasks to off" ]
}
@test "editor default only (key absent) → FAIL, and the note says the default doesn't count" {
  mkdir -p "$HOME/$U"; echo '{"editor.fontSize": 13}' > "$HOME/$U/settings.json"
  chk; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *"the editor's default doesn't count"* ]]
}
@test "a file without the setting is a FAIL even when another can't be read, and the note names it" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  mkdir -p "$HOME/$U/profiles/abc"
  echo '{"task.allowAutomaticTasks":"off"}' > "$HOME/$U/settings.json"; chmod 000 "$HOME/$U/settings.json"
  echo '{}' > "$HOME/$U/profiles/abc/settings.json"
  chk; chmod 600 "$HOME/$U/settings.json"
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *profiles/abc* ]]; [[ "$(field note)" == *"Could not read: ~/"* ]]
}
