load helpers

setup() {
  setup_env
  L="$HOME/Library/LaunchAgents"; mkdir -p "$L"
  stub launchctl '[ "$1" = print ] && case " ${LOADED:-} " in *" ${2##*/} "*) exit 0 ;; esac; exit 1'
}
chk() { run /bin/bash "$REPO/checks/macos/$1.sh"; }
agent() {  # LABEL SCRIPT_BODY [WEEKDAY]
  printf '#!/bin/zsh\n%s\n' "$2" > "$HOME/$1.sh"
  plutil -create xml1 "$L/$1.plist"; plutil -insert Label -string "$1" "$L/$1.plist"
  plutil -insert ProgramArguments -json "[\"/bin/zsh\",\"$HOME/$1.sh\"]" "$L/$1.plist"
  [ -n "${3:-}" ] && plutil -insert StartCalendarInterval -json "{\"Weekday\":$3,\"Hour\":9}" "$L/$1.plist"
  return 0
}
weekly_ran() {  # [STAMP] — weekly-last with that mtime (touch -t format), or now
  mkdir -p "$DEVWARD_REPORTS"; : > "$DEVWARD_REPORTS/weekly-last"
  [ -z "${1:-}" ] || touch -t "$1" "$DEVWARD_REPORTS/weekly-last"
}

@test "BL-AU-01 weekly brew job loaded → PASS; not loaded → FAIL; not weekly or not updating → FAIL" {
  agent upd 'brew update && brew upgrade' 1
  LOADED=upd chk BL-AU-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *upd* ]]
  chk BL-AU-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not loaded"* ]]
  rm "$L/upd.plist"; agent daily 'brew upgrade'
  LOADED=daily chk BL-AU-01; [ "$(field status)" = FAIL ]
  agent other 'echo hi' 3
  LOADED=other chk BL-AU-01; [ "$(field status)" = FAIL ]
}
@test "BL-AU-01 a weekly job whose script can't be read → ERROR with evidence" {
  agent upd 'brew update' 1
  chmod 000 "$HOME/upd.sh"
  LOADED=upd chk BL-AU-01; chmod 644 "$HOME/upd.sh"
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$(field evidence)" != *"$HOME"* ]]
}
@test "BL-AU-02 missing → FAIL; installed, loaded, recent review → PASS; overdue → FAIL" {
  chk BL-AU-02; [ "$(field status)" = FAIL ]
  agent io.github.b0dea.devward.weekly 'true' 3
  weekly_ran
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-02; [ "$(field status)" = PASS ]
  weekly_ran 202001010000
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *overdue* ]]
  chk BL-AU-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not loaded"* ]]
}
@test "BL-AU-02 dates the last review from weekly-last, not from a manual /posture run" {
  agent io.github.b0dea.devward.weekly 'true' 3
  weekly_ran 202001010000
  mkdir -p "$DEVWARD_REPORTS/x"; echo "{\"run\":\"$(date -u +%Y%m%dT%H%M%SZ)\",\"results\":[]}" > "$DEVWARD_REPORTS/x/results.json"
  ln -sfn x "$DEVWARD_REPORTS/latest"
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *overdue* ]]
}
@test "BL-AU-02 never completed a review: fresh install → PASS with a note; old install → FAIL" {
  agent io.github.b0dea.devward.weekly 'true' 3
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-02; [ "$(field status)" = PASS ]; [ -n "$(field note)" ]
  touch -t 202001010000 "$L/io.github.b0dea.devward.weekly.plist"
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"never completed a review"* ]]
}
@test "BL-AU-02 passes while the weekly review itself is running" {
  agent io.github.b0dea.devward.weekly 'true' 3
  weekly_ran 202001010000
  DEVWARD_WEEKLY_RUN=1 LOADED=io.github.b0dea.devward.weekly chk BL-AU-02; [ "$(field status)" = PASS ]
  DEVWARD_WEEKLY_RUN=1 chk BL-AU-02; [ "$(field status)" = FAIL ]
}
@test "BL-AU-01 an inline zsh -c update job, and a zsh -l script job → PASS" {
  agent inl 'true' 1
  plutil -replace ProgramArguments -json '["/bin/zsh","-lc","brew update && brew upgrade"]' "$L/inl.plist"
  LOADED=inl chk BL-AU-01; [ "$(field status)" = PASS ]
  rm "$L/inl.plist"; agent scr 'brew upgrade' 1
  plutil -replace ProgramArguments -json "[\"/bin/zsh\",\"-l\",\"$HOME/scr.sh\"]" "$L/scr.plist"
  LOADED=scr chk BL-AU-01; [ "$(field status)" = PASS ]
  rm "$L/scr.plist"; agent noop 'true' 1
  plutil -replace ProgramArguments -json '["/bin/zsh","-c","echo hi"]' "$L/noop.plist"
  LOADED=noop chk BL-AU-01; [ "$(field status)" = FAIL ]
}
@test "BL-AU-02 weekly-last that can't be dated → ERROR with evidence" {
  agent io.github.b0dea.devward.weekly 'true' 3
  weekly_ran
  stub stat 'exit 1'
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}

weekly_tree() {  # a copy of checks/ with two fake controls; FLIP=1 makes the second one FAIL
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W/checks/fake"
  cp -R "$REPO/checks/lib" "$W/checks/"; cp "$REPO"/checks/*.sh "$W/checks/"
  printf '#!/bin/bash\necho "{\\"id\\":\\"BL-OS-01\\",\\"status\\":\\"PASS\\",\\"evidence\\":\\"\\",\\"note\\":\\"\\"}"\n' > "$W/checks/fake/a.sh"
  printf '#!/bin/bash\ns=PASS; [ -f "%s/flip" ] && s=FAIL\necho "{\\"id\\":\\"BL-OS-02\\",\\"status\\":\\"$s\\",\\"evidence\\":\\"\\",\\"note\\":\\"\\"}"\n' "$BATS_TEST_TMPDIR" > "$W/checks/fake/b.sh"
  echo '[{"id":"BL-OS-01","title":"FileVault on","layer":"baseline","level":"MUST","source":"§1","check":"checks/fake/a.sh"},{"id":"BL-OS-02","title":"Firewall on","layer":"baseline","level":"MUST","source":"§1","check":"checks/fake/b.sh"}]' > "$W/controls.json"
  export DEVWARD_REPO="$W" DEVWARD_CONTROLS="$W/controls.json"
  stub sw_vers 'echo 15.7'
  stub osascript 'printf "%s\n" "$*" >> "$BATS_TEST_TMPDIR/notified"'
  stub brew 'echo "brew $*" >> "$BATS_TEST_TMPDIR/brew-calls"; [ "$1" = vulns ] && echo "{\"findings\":[]}"; exit 0'
  # weekly.sh takes the login shell's PATH, which puts inherited entries last: keep the stubs first.
  printf 'export PATH="%s/bin:$PATH"\n' "$BATS_TEST_TMPDIR" > "$HOME/.zlogin"
  # weekly.sh runs only a copy that is exactly a signed release, as on a person's Mac. The fake checks and
  # controls.json stay untracked, so a test can change them without that counting as a local change.
  git -C "$W" init -q -b main; printf '%s\n' /checks/fake/ /controls.json >> "$W/.git/info/exclude"
  signers_into "$W"; commit "$W"; sign_release "$W" v0.1.0
  person_session
}
refused() {  # the run stopped before the review: no report, no Homebrew step, no weekly-last
  [ "$status" -eq 1 ]; [[ "$output" == *"Refused to run the review: "* ]]
  [ ! -e "$DEVWARD_REPORTS/latest" ]; [ ! -e "$BATS_TEST_TMPDIR/brew-calls" ]; [ ! -e "$DEVWARD_REPORTS/weekly-last" ]
}
@test "weekly.sh refuses a copy with local changes: says why, notifies, exits 1 and leaves weekly-last alone" {
  weekly_tree
  echo '# edited' >> "$W/checks/lib/common.sh"
  run "$W/checks/weekly.sh"; refused
  [[ "$output" == *"local changes"* ]]; grep -q "weekly security review did not run" "$BATS_TEST_TMPDIR/notified"
}
@test "weekly.sh refuses a copy that isn't a signed release, though nothing is uncommitted (A18)" {
  weekly_tree
  echo '# edited' >> "$W/checks/lib/common.sh"; commit "$W"
  run "$W/checks/weekly.sh"; refused
  [[ "$output" == *"not on a signed release"* ]]; grep -q "not exactly a signed release" "$BATS_TEST_TMPDIR/notified"
}
@test "weekly.sh notifies only about controls that newly fail, by title, and says how to open devward" {
  # No DEVWARD_NO_NOTIFY here: this test must observe the notification through the osascript stub.
  weekly_tree
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]; [ ! -e "$BATS_TEST_TMPDIR/notified" ]
  touch "$BATS_TEST_TMPDIR/flip"; sleep 1
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  grep -q 'Newly failing: Firewall on\.' "$BATS_TEST_TMPDIR/notified"
  grep -q 'open the Terminal app, type cd ' "$BATS_TEST_TMPDIR/notified"; grep -q 'type /posture' "$BATS_TEST_TMPDIR/notified"
  ! grep -q -e BL-OS-02 -e 'possible malware' "$BATS_TEST_TMPDIR/notified"
  rm "$BATS_TEST_TMPDIR/notified"; sleep 1
  run "$W/checks/weekly.sh"; [ ! -e "$BATS_TEST_TMPDIR/notified" ]
}
@test "weekly.sh sends its own plain notification for a newly failing urgent control, unless the FAIL is a set-up step" {
  weekly_tree
  jq 'map(if .id == "BL-OS-02" then .title = "No live malware" | .urgent = true | .not_urgent_if = "No accepted baseline yet" else . end)' "$W/controls.json" > "$W/c2.json"
  mv "$W/c2.json" "$W/controls.json"
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]; [ ! -e "$BATS_TEST_TMPDIR/notified" ]
  touch "$BATS_TEST_TMPDIR/flip"; sleep 1
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  grep -q 'possible malware' "$BATS_TEST_TMPDIR/notified"; grep -q 'No live malware' "$BATS_TEST_TMPDIR/notified"
  grep -q 'Turn off Wi-Fi' "$BATS_TEST_TMPDIR/notified"; grep -q 'docs/if-red.md' "$BATS_TEST_TMPDIR/notified"
  ! grep -q 'Newly failing' "$BATS_TEST_TMPDIR/notified"
  # The same FAIL with the set-up evidence (no baseline accepted yet) is an ordinary one.
  rm -f "$BATS_TEST_TMPDIR/flip" "$BATS_TEST_TMPDIR/notified"; sleep 1
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  printf '#!/bin/bash\necho "{\\"id\\":\\"BL-OS-02\\",\\"status\\":\\"FAIL\\",\\"evidence\\":\\"No accepted baseline yet\\",\\"note\\":\\"\\"}"\n' > "$W/checks/fake/b.sh"
  sleep 1; run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  grep -q 'Newly failing: No live malware\.' "$BATS_TEST_TMPDIR/notified"; ! grep -q 'possible malware' "$BATS_TEST_TMPDIR/notified"
}
@test "the devward-weekly launcher is executable, runs weekly.sh and passes on its status" {
  [ -x "$REPO/checks/devward-weekly" ]
  weekly_tree; export DEVWARD_NO_NOTIFY=1; cp "$REPO/checks/devward-weekly" "$W/checks/"
  run "$W/checks/devward-weekly"; [ "$status" -eq 0 ]; [ -e "$DEVWARD_REPORTS/weekly-last" ]
  echo 'not json' > "$W/controls.json"
  run "$W/checks/devward-weekly"; [ "$status" -eq 1 ]
}
@test "weekly.sh touches weekly-last when the review ran, and not when it couldn't" {
  weekly_tree; export DEVWARD_NO_NOTIFY=1
  [ ! -e "$DEVWARD_REPORTS/weekly-last" ]
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]; [ -e "$DEVWARD_REPORTS/weekly-last" ]
  rm "$DEVWARD_REPORTS/weekly-last"
  echo 'not json' > "$W/controls.json"
  run "$W/checks/weekly.sh"; [ "$status" -eq 1 ]; [ ! -e "$DEVWARD_REPORTS/weekly-last" ]
}
@test "weekly.sh runs the checks with the PATH of the login shell" {
  weekly_tree; export DEVWARD_NO_NOTIFY=1
  mkdir -p "$BATS_TEST_TMPDIR/loginbin"; printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/loginbin/devward-login-tool"; chmod +x "$BATS_TEST_TMPDIR/loginbin/devward-login-tool"
  printf 'export PATH="%s/loginbin:$PATH"\n' "$BATS_TEST_TMPDIR" >> "$HOME/.zlogin"
  printf '#!/bin/bash\ncommand -v devward-login-tool >> "%s/seen"\necho "{\\"id\\":\\"BL-OS-01\\",\\"status\\":\\"PASS\\",\\"evidence\\":\\"\\",\\"note\\":\\"\\"}"\n' "$BATS_TEST_TMPDIR" > "$W/checks/fake/a.sh"
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/seen")" = "$BATS_TEST_TMPDIR/loginbin/devward-login-tool" ]
}
@test "weekly.sh keeps its PATH when the login shell fails" {
  weekly_tree; export DEVWARD_NO_NOTIFY=1
  mkdir -p "$BATS_TEST_TMPDIR/loginbin"
  printf 'export PATH="%s/loginbin:$PATH"\nexit 3\n' "$BATS_TEST_TMPDIR" >> "$HOME/.zlogin"
  printf '#!/bin/bash\necho "$PATH" >> "%s/seen"\necho "{\\"id\\":\\"BL-OS-01\\",\\"status\\":\\"PASS\\",\\"evidence\\":\\"\\",\\"note\\":\\"\\"}"\n' "$BATS_TEST_TMPDIR" > "$W/checks/fake/a.sh"
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  run grep -c "loginbin" "$BATS_TEST_TMPDIR/seen"; [ "$output" = 0 ]
}
@test "weekly.sh runs a KnockKnock scan when KnockKnock is installed, and keeps only valid JSON" {
  weekly_tree; export DEVWARD_NO_NOTIFY=1
  mkdir -p "$DEVWARD_SYSROOT/Applications/KnockKnock.app"
  stub open 'while [ $# -gt 0 ]; do [ "$1" = --stdout ] && { echo "{\"Launch Items\":[{\"path\":\"/x\"}]}" > "$2"; }; shift; done'
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  jq -e '."Launch Items"[0].path == "/x"' "$DEVWARD_REPORTS/knockknock/latest.json"
  stub open 'while [ $# -gt 0 ]; do [ "$1" = --stdout ] && { echo "garbage" > "$2"; }; shift; done'
  sleep 1; run "$W/checks/weekly.sh"
  jq -e '."Launch Items"[0].path == "/x"' "$DEVWARD_REPORTS/knockknock/latest.json"
}
@test "weekly.sh: the real BL-AU-02 does not flag the run that ends an overdue gap" {
  weekly_tree
  jq -c --slurpfile c "$REPO/controls/controls.json" '. + [$c[0][] | select(.id == "BL-AU-02")]' "$W/controls.json" > "$W/c2.json"; mv "$W/c2.json" "$W/controls.json"
  mkdir -p "$W/checks/macos"; cp "$REPO/checks/macos/BL-AU-02.sh" "$W/checks/macos/"
  agent io.github.b0dea.devward.weekly 'true' 3
  stub launchctl 'exit 0'
  weekly_ran 202001010000
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  [ "$(jq -r '.results[] | select(.id == "BL-AU-02") | .status' "$DEVWARD_REPORTS/latest/results.json")" = PASS ]
  [ ! -e "$BATS_TEST_TMPDIR/notified" ]
}
@test "BL-AU-01 never reads a job script inside a private folder, and says only that one was excluded" {
  mkdir -p "$HOME/Secret"; agent upd 'brew update' 1; mv "$HOME/upd.sh" "$HOME/Secret/upd.sh"
  plutil -replace ProgramArguments -json "[\"/bin/zsh\",\"$HOME/Secret/upd.sh\"]" "$L/upd.plist"
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  LOADED=upd chk BL-AU-01
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  [[ "$output" == *"a private folder was excluded"* ]]; [[ "$output" != *Secret* ]]
  agent pub 'brew upgrade' 1
  LOADED="upd pub" chk BL-AU-01; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"a private folder was excluded"* ]]
}
@test "weekly.sh: Homebrew updates, then a notification counts the formulae with a released fix; it never upgrades" {
  weekly_tree
  cp "$REPO/tests/fixtures/brew-vulns.json" "$BATS_TEST_TMPDIR/vulns.json"
  stub brew 'echo "brew $*" >> "$BATS_TEST_TMPDIR/brew-calls"; [ "$1" = vulns ] || exit 0; cat "$BATS_TEST_TMPDIR/vulns.json"; exit 1'
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/brew-calls")" = "brew update"$'\n'"brew vulns --fix-available --json" ]
  grep -q '2 formulae have a vulnerability with a released fix' "$BATS_TEST_TMPDIR/notified"
  grep -q 'Run brew upgrade' "$BATS_TEST_TMPDIR/notified"
  [[ "$output" == *'"formula": "examplelib"'* ]]; [[ "$output" == *"Homebrew: 2 formula(e)"* ]]
  [ -e "$DEVWARD_REPORTS/weekly-last" ]
}
@test "weekly.sh: no formula with a released fix, no Homebrew notification" {
  weekly_tree
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew: 0 formula(e)"* ]]; [ ! -e "$BATS_TEST_TMPDIR/notified" ]
}
@test "weekly.sh: a failed or timed-out Homebrew step is logged and the weekly run still succeeds" {
  weekly_tree; export DEVWARD_NO_NOTIFY=1
  stub brew '[ "$1" = vulns ] && { echo garbage; exit 1; }; exit 1'
  run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  [[ "$output" == *"brew update failed or timed out (exit 1)"* ]]; [[ "$output" == *"brew vulns failed or gave no JSON"* ]]
  [ -e "$DEVWARD_REPORTS/weekly-last" ]
  stub brew 'sleep 30'
  t0="$(date +%s)"; DEVWARD_BREW_TIMEOUT=2 run "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  [ $(( $(date +%s) - t0 )) -lt 25 ]; [[ "$output" == *"(exit 142)"* ]]
}
@test "weekly.sh without Homebrew skips the step and says so" {
  weekly_tree; export DEVWARD_NO_NOTIFY=1
  rm "$BATS_TEST_TMPDIR/bin/brew"
  printf 'export PATH="%s/bin:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR" > "$HOME/.zlogin"
  # The inherited PATH leaves Homebrew out too: if the login-shell probe fails, weekly.sh keeps it.
  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$W/checks/weekly.sh"; [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew step skipped: brew not found"* ]]; [ -e "$DEVWARD_REPORTS/weekly-last" ]
}
@test "BL-AU-01 devward's own weekly job doesn't count: by its label, or this repo's launcher or script under either spelling" {
  grep -q 'brew upgrade' "$REPO/checks/weekly.sh"  # its notification names the command, which must not count
  agent io.github.b0dea.devward.weekly 'true' 3
  plutil -replace ProgramArguments -json "[\"$REPO/checks/devward-weekly\"]" "$L/io.github.b0dea.devward.weekly.plist"
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-01
  [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "No weekly job that runs brew upgrade" ]
  plutil -replace ProgramArguments -json "[\"/bin/bash\",\"$REPO/checks/weekly.sh\"]" "$L/io.github.b0dea.devward.weekly.plist"
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-01; [ "$(field status)" = FAIL ]
  mkdir -p "$HOME/copy"; cp "$REPO/checks/weekly.sh" "$HOME/copy/"  # the label alone is enough
  plutil -replace ProgramArguments -json "[\"/bin/bash\",\"$HOME/copy/weekly.sh\"]" "$L/io.github.b0dea.devward.weekly.plist"
  LOADED=io.github.b0dea.devward.weekly chk BL-AU-01; [ "$(field status)" = FAIL ]
  # Under another label: this repo's launcher or script, by the path DEVWARD_REPO names or the physical one behind a symlink.
  mkdir -p "$HOME/real/checks"; cp "$REPO/checks/weekly.sh" "$REPO/checks/devward-weekly" "$HOME/real/checks/"
  ln -s "$HOME/real" "$HOME/link"; P="$(cd "$HOME/real" && pwd -P)"
  for s in "$P/checks/devward-weekly" "$P/checks/weekly.sh" "$HOME/link/checks/weekly.sh"; do
    agent other 'true' 1; plutil -replace ProgramArguments -json "[\"/bin/bash\",\"$s\"]" "$L/other.plist"
    LOADED=other run env DEVWARD_REPO="$HOME/link" /bin/bash "$REPO/checks/macos/BL-AU-01.sh"
    [ "$(field status)" = FAIL ] || { echo "counted: $s"; false; }
  done
  rm "$L/other.plist"; agent upd 'brew update && brew upgrade && brew vulns' 1
  LOADED="io.github.b0dea.devward.weekly upd" chk BL-AU-01
  [ "$(field status)" = PASS ]; [ "$(field evidence)" = "Weekly update job: upd" ]
}
@test "BL-AU-01 counts brew upgrade, not brew update alone" {
  agent upd 'brew update' 1
  LOADED=upd chk BL-AU-01; [ "$(field status)" = FAIL ]
  agent upd $'if brew update; then\n  /opt/homebrew/bin/brew upgrade --greedy\nfi' 1
  LOADED=upd chk BL-AU-01; [ "$(field status)" = PASS ]
}
