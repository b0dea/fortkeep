load helpers

setup() {
  setup_env; fix_tree
  stub launchctl 'echo "$*" >> "$BATS_TEST_TMPDIR/launchctl.log"; case "$1" in print) [ -f "$BATS_TEST_TMPDIR/loaded" ] ;; bootstrap) [ ! -f "$BATS_TEST_TMPDIR/nobootstrap" ] && touch "$BATS_TEST_TMPDIR/loaded" ;; bootout) rm -f "$BATS_TEST_TMPDIR/loaded" ;; esac'
}
fix() { run /bin/bash "$T/fixes/macos/BL-AU-02.sh" "$1"; }
approve() { date +%s > "$DEVWARD_REPORTS/.approvals/BL-AU-02.$1"; }
P() { printf '%s\n' "$HOME/Library/LaunchAgents/io.github.b0dea.devward.weekly.plist"; }
au02() { /bin/bash "$T/checks/macos/BL-AU-02.sh" | jq -r .status; }

@test "refuses without approval and touches nothing" {
  fix apply; [ "$status" -eq 4 ]; [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
}
@test "apply writes and loads the weekly job, BL-AU-02 passes; undo unloads and removes it" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  [ "$(plutil -extract ProgramArguments.0 raw "$(P)")" = "$(cd "$T" && pwd -P)/checks/devward-weekly" ]
  run plutil -extract ProgramArguments.1 raw "$(P)"; [ "$status" -ne 0 ]
  [ "$(plutil -extract StartCalendarInterval.Weekday raw "$(P)")" = 3 ]
  [ "$(plutil -extract StandardOutPath raw "$(P)")" = "$HOME/Library/Logs/devward-weekly.log" ]
  grep -q '^bootstrap gui/' "$BATS_TEST_TMPDIR/launchctl.log"
  grep -q '| BL-AU-02 | apply |' "$DEVWARD_REPORTS/change-log.md"
  [ "$(au02)" = PASS ]
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ ! -e "$(P)" ]; [ ! -e "$BATS_TEST_TMPDIR/loaded" ]
  [ "$(au02)" = FAIL ]
}
@test "the installing session's CLAUDE_CONFIG_DIR is passed to the job" {
  approve apply; CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/ccd" fix apply; [ "$status" -eq 0 ]
  [ "$(plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw "$(P)")" = "$BATS_TEST_TMPDIR/ccd" ]
}
@test "nothing to change when the job is installed and loaded" {
  approve apply; fix apply
  approve apply; fix apply; [ "$status" -eq 0 ]; [[ "$output" == *"nothing to change"* ]]
}
@test "a different CLAUDE_CONFIG_DIR in the installing session reinstalls the job" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  approve apply; CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/ccd" fix apply; [ "$status" -eq 0 ]
  [[ "$output" != *"nothing to change"* ]]
  [ "$(plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw "$(P)")" = "$BATS_TEST_TMPDIR/ccd" ]
  approve apply; CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/ccd" fix apply; [[ "$output" == *"nothing to change"* ]]
  approve apply; fix apply; [[ "$output" != *"nothing to change"* ]]
  run plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw "$(P)"; [ "$status" -ne 0 ]
}
@test "a job from an earlier version, run as /bin/bash weekly.sh, is reinstalled under the launcher's name" {
  mkdir -p "$HOME/Library/LaunchAgents"; plutil -create xml1 "$(P)"
  plutil -insert ProgramArguments -json "[\"/bin/bash\",\"$(cd "$T" && pwd -P)/checks/weekly.sh\"]" "$(P)"
  touch "$BATS_TEST_TMPDIR/loaded"
  approve apply; fix apply; [ "$status" -eq 0 ]; [[ "$output" != *"nothing to change"* ]]
  [ "$(plutil -extract ProgramArguments.0 raw "$(P)")" = "$(cd "$T" && pwd -P)/checks/devward-weekly" ]
}
@test "a failed backup stops with nothing changed and no leftover backup folder" {
  mkdir -p "$HOME/Library/LaunchAgents"; ln -s "$BATS_TEST_TMPDIR/nowhere" "$(P)"
  approve apply; fix apply; [ "$status" -eq 3 ]; [[ "$output" == *"nothing was changed"* ]]
  [ -L "$(P)" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
  [ -z "$(ls "$DEVWARD_BACKUPS/BL-AU-02" 2>/dev/null)" ]
}
@test "a plist write failure puts the old file back, says so, and leaves no backup" {
  mkdir -p "$HOME/Library/LaunchAgents"; printf 'old\n' > "$(P)"
  stub plutil 'case "$1" in -insert|insert) exit 1 ;; *) exec /usr/bin/plutil "$@" ;; esac'
  approve apply; fix apply; [ "$status" -eq 3 ]
  [[ "$output" == *"could not write"* ]]; [[ "$output" == *"put back"* ]]; [[ "$output" == *"nothing was changed"* ]]
  [ "$(cat "$(P)")" = old ]; [ ! -e "$BATS_TEST_TMPDIR/loaded" ]
  [ -z "$(ls "$DEVWARD_BACKUPS/BL-AU-02" 2>/dev/null)" ]
  run grep -q '^bootstrap' "$BATS_TEST_TMPDIR/launchctl.log"; [ "$status" -eq 1 ]
}
@test "a plist write failure with no old file leaves no plist" {
  stub plutil 'case "$1" in -insert|insert) exit 1 ;; *) exec /usr/bin/plutil "$@" ;; esac'
  approve apply; fix apply; [ "$status" -eq 3 ]; [[ "$output" == *"put back"* ]]
  [ ! -e "$(P)" ]; [ -z "$(ls "$DEVWARD_BACKUPS/BL-AU-02" 2>/dev/null)" ]
}
@test "written but not loaded: MANUAL, sealed, and undo still works" {
  touch "$BATS_TEST_TMPDIR/nobootstrap"
  approve apply; fix apply; [ "$status" -eq 3 ]; [[ "$output" == *"didn't load"* ]]
  [ -f "$(P)" ]; ls "$DEVWARD_BACKUPS"/BL-AU-02/*/sealed.tsv
  approve undo; fix undo; [ "$status" -eq 0 ]; [ ! -e "$(P)" ]
}
@test "undo stops before unloading when the plist was edited after the fix" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  printf '\n<!-- mine -->\n' >> "$(P)"
  : > "$BATS_TEST_TMPDIR/launchctl.log"
  approve undo; fix undo; [ "$status" -eq 6 ]; [[ "$output" == *"undo stopped"* ]]
  [ -f "$BATS_TEST_TMPDIR/loaded" ]; grep -q 'mine' "$(P)"
  run grep -c '^bootout' "$BATS_TEST_TMPDIR/launchctl.log"; [ "$output" = 0 ]
}
@test "undo with nothing applied exits 5 and unloads nothing" {
  approve undo; fix undo; [ "$status" -eq 5 ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
}
