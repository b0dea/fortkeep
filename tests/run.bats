load helpers

setup() {
  setup_env
  T="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$T/checks/fake"
  cp -R "$REPO/checks/lib" "$T/checks/"
  cp "$REPO"/checks/*.sh "$T/checks/"
  export FORTKEEP_REPO="$T" FORTKEEP_CONTROLS="$T/controls.json"
  stub sw_vers 'echo 15.7.9'
  mk() { printf '#!/bin/bash\n%s\n' "$2" > "$T/checks/fake/$1.sh"; }
  mk ok   'echo "{\"id\":\"BL-OS-01\",\"status\":\"PASS\",\"evidence\":\"fine\",\"note\":\"\"}"'
  mk bad  'echo "{\"id\":\"BL-OS-02\",\"status\":\"FAIL\",\"evidence\":\"off\",\"note\":\"\"}"'
  mk slow 'sleep 5; echo "{}"'
  mk junk 'echo not-json'
  mk ok6  'echo "{\"id\":\"BL-OS-06\",\"status\":\"PASS\",\"evidence\":\"x\",\"note\":\"\"}"'
  mk rd   'cat >/dev/null; echo "{\"id\":\"BL-OS-05\",\"status\":\"PASS\",\"evidence\":\"r\",\"note\":\"\"}"'
  mk ov   'echo "{\"id\":\"OV-PX-01\",\"status\":\"PASS\",\"evidence\":\"x\",\"note\":\"\"}"'
  cat > "$FORTKEEP_CONTROLS" <<'EOF'
[
 {"id":"BL-OS-01","title":"One","layer":"baseline","level":"MUST","source":"§1","check":"checks/fake/ok.sh"},
 {"id":"BL-OS-02","title":"Two","layer":"baseline","level":"MUST","source":"§1","check":"checks/fake/bad.sh"},
 {"id":"BL-OS-03","title":"Three","layer":"baseline","level":"SHOULD","source":"§1","check":"checks/fake/slow.sh","timeout":1},
 {"id":"BL-OS-04","title":"Four","layer":"baseline","level":"NICE","source":"§1","check":"checks/fake/junk.sh"},
 {"id":"BL-OS-05","title":"Five","layer":"baseline","level":"NICE","source":"§1","check":"checks/fake/rd.sh"},
 {"id":"BL-OS-06","title":"Six","layer":"baseline","level":"NICE","source":"§1","check":"checks/fake/ok6.sh"},
 {"id":"OV-PX-01","title":"Proxy","layer":"overlay:tls-proxy","level":"SHOULD","check":"checks/fake/ov.sh"}
]
EOF
}

res() { jq -r --arg id "$1" '.results[] | select(.id==$id) | .'"$2" "$FORTKEEP_REPORTS/latest/results.json"; }

@test "runs checks and records PASS, FAIL, timeout and junk as ERROR" {
  run "$T/checks/run.sh"
  [ "$status" -eq 0 ]
  [ "$(res BL-OS-01 status)" = PASS ]
  [ "$(res BL-OS-02 status)" = FAIL ]
  [ "$(res BL-OS-03 status)" = ERROR ]
  [[ "$(res BL-OS-03 evidence)" == *"timed out"* ]]
  [ "$(res BL-OS-04 status)" = ERROR ]
  [ "$(res BL-OS-02 title)" = Two ]
  [ "$(jq -r .macos "$FORTKEEP_REPORTS/latest/results.json")" = 15.7.9 ]
}

@test "overlay controls run only when configured" {
  "$T/checks/run.sh"
  [ -z "$(res OV-PX-01 status)" ]
  "$T/checks/configure.sh" --overlays "tls-proxy" --teach no
  sleep 1
  "$T/checks/run.sh"
  [ "$(res OV-PX-01 status)" = PASS ]
}

@test "configure rejects unknown overlays" {
  run "$T/checks/configure.sh" --overlays "nope" --teach yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown overlay(s): nope"* ]]
}

said_accept() { mkdir -p "$T/reports/.approvals"; printf '%s\n' "$2" > "$T/reports/.approvals/$1.accept"; }  # ID REASON — the hook recorded Accept <ID> to the question naming REASON

@test "accepted, after the person's Accept answer, turns FAIL into ACCEPTED with the reason" {
  said_accept BL-OS-02 "deliberate, my decision"
  "$T/checks/accept.sh" BL-OS-02 "deliberate, my decision"
  "$T/checks/run.sh"
  [ "$(res BL-OS-02 status)" = ACCEPTED ]
  [ "$(res BL-OS-02 note)" = "deliberate, my decision" ]
}

@test "accept refuses unknown ids" {
  run "$T/checks/accept.sh" BL-XX-99 "x"
  [ "$status" -eq 2 ]
}

@test "A9: accept needs the person: without their recorded Accept answer it refuses, and an answer is used once" {
  run "$T/checks/accept.sh" BL-OS-02 "x"; [ "$status" -eq 4 ]; [[ "$output" == *"no approval"* ]]
  said_accept BL-OS-02 x; touch -t 202001010000 "$T/reports/.approvals/BL-OS-02.accept"
  run "$T/checks/accept.sh" BL-OS-02 "x"; [ "$status" -eq 4 ]; [[ "$output" == *expired* ]]
  said_accept BL-OS-01 x
  run "$T/checks/accept.sh" BL-OS-02 "x"; [ "$status" -eq 4 ]
  [ "$(jq 'has("BL-OS-02")' "$FORTKEEP_ACCEPTED")" = false ]
  said_accept BL-OS-02 x
  run "$T/checks/accept.sh" BL-OS-02 "x"; [ "$status" -eq 0 ]; [ ! -e "$T/reports/.approvals/BL-OS-02.accept" ]
  run "$T/checks/accept.sh" --remove BL-OS-02; [ "$status" -eq 0 ]
}

@test "an Accept answer counts only for the reason its question named: the agent can't swap in its own words" {
  said_accept BL-OS-02 "I use another firewall"
  run "$T/checks/accept.sh" BL-OS-02 "the person said it is fine"; [ "$status" -eq 4 ]; [[ "$output" == *"another reason"* ]]
  [ "$(jq 'has("BL-OS-02")' "$FORTKEEP_ACCEPTED")" = false ]
  [ ! -e "$T/reports/.approvals/BL-OS-02.accept" ]   # a mismatch uses the answer up
  run "$T/checks/ask.sh" BL-OS-02 accept "I use another firewall"; [ "$status" -eq 0 ]
  [[ "$(field question)" == *'"I use another firewall"'* ]]
  run "$T/checks/ask.sh" BL-OS-02 accept; [ "$status" -eq 2 ]   # no question without the reason it records
}

@test "an accept reason is one line of at most 300 characters with no control characters or backslashes" {
  # A backslash could be approved but never passed on: the guard refuses it in the agent's command.
  long="$(printf 'x%.0s' $(seq 301))"
  for r in "" "$(printf 'one\ntwo')" "$(printf 'tab\there')" "$(printf 'esc\033[2J')" "$long" 'C:\\keys'; do
    said_accept BL-OS-02 "$r"
    run "$T/checks/accept.sh" BL-OS-02 "$r"; [ "$status" -eq 2 ]
    run "$T/checks/ask.sh" BL-OS-02 accept "$r"; [ "$status" -eq 2 ]
  done
  [ "$(jq 'has("BL-OS-02")' "$FORTKEEP_ACCEPTED")" = false ]
  said_accept BL-OS-02 "${long%x}"
  run "$T/checks/accept.sh" BL-OS-02 "${long%x}"; [ "$status" -eq 0 ]
}

@test "--only runs one control" {
  "$T/checks/run.sh"
  sleep 1
  "$T/checks/run.sh" --only BL-OS-01
  run jq '.results | length' "$FORTKEEP_REPORTS/latest/results.json"
  [ "$output" -eq 6 ]
  [ "$(jq -c .rechecked "$FORTKEEP_REPORTS/latest/results.json")" = '["BL-OS-01"]' ]
}

@test "--only keeps the full results, updates the rechecked row, and diff shows it" {
  "$T/checks/run.sh"
  sleep 1
  mk bad 'echo "{\"id\":\"BL-OS-02\",\"status\":\"PASS\",\"evidence\":\"on\",\"note\":\"\"}"'
  run "$T/checks/run.sh" --only BL-OS-02
  [ "$status" -eq 0 ]
  [ "$(jq '.results | length' "$FORTKEEP_REPORTS/latest/results.json")" -eq 6 ]
  [ "$(res BL-OS-02 status)" = PASS ]
  [ "$(res BL-OS-01 status)" = PASS ]
  [ "$(res BL-OS-03 status)" = ERROR ]
  [ "$(res BL-OS-02 title)" = Two ]
  [ "$(jq -c .rechecked "$FORTKEEP_REPORTS/latest/results.json")" = '["BL-OS-02"]' ]
  run "$T/checks/diff.sh"
  [[ "$output" == *"BL-OS-02: FAIL → PASS"* ]]
}

@test "--only with an unknown control exits 2 and keeps latest" {
  "$T/checks/run.sh"
  before="$(readlink "$FORTKEEP_REPORTS/latest")"
  sleep 1
  run "$T/checks/run.sh" --only BL-XX-99
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown control: BL-XX-99"* ]]
  [ "$(readlink "$FORTKEEP_REPORTS/latest")" = "$before" ]
}

@test "--only without a previous full run exits 2" {
  run "$T/checks/run.sh" --only BL-OS-01
  [ "$status" -eq 2 ]
  [[ "$output" == *"run a full review first"* ]]
  [ ! -e "$FORTKEEP_REPORTS/latest" ]
}

# the hook recorded "Add private folder" to the question naming FOLDER (absolute, as checks/ask.sh prints it)
said_private() { mkdir -p "$T/reports/.approvals"; printf '%s\n' "$1" > "$T/reports/.approvals/private.add"; }

@test "A15: private.sh add needs the person: without their recorded answer it refuses and adds nothing; an answer is used once" {
  run "$T/checks/private.sh" add "~/.ssh"; [ "$status" -eq 4 ]; [[ "$output" == *"no approval"* ]]
  [ ! -e "$FORTKEEP_PRIVATE_PATHS" ]
  said_private "$HOME/.ssh"; touch -t 202001010000 "$T/reports/.approvals/private.add"
  run "$T/checks/private.sh" add "~/.ssh"; [ "$status" -eq 4 ]; [[ "$output" == *expired* ]]
  said_private "$HOME/Private"
  run "$T/checks/private.sh" add "~/Private"; [ "$status" -eq 0 ]; [ ! -e "$T/reports/.approvals/private.add" ]
  run "$T/checks/private.sh" add "~/.ssh"; [ "$status" -eq 4 ]
  [ "$(cat "$FORTKEEP_PRIVATE_PATHS")" = "$HOME/Private" ]
}

@test "A21: an answer adds only the folder its question named, and never a path spelled with . or .." {
  said_private "$HOME/One"
  run "$T/checks/private.sh" add "~/Two"; [ "$status" -eq 4 ]; [[ "$output" == *"another folder"* ]]
  [[ "$output" != *One* ]]; [[ "$output" != *Two* ]]
  [ ! -e "$T/reports/.approvals/private.add" ]; [ ! -e "$FORTKEEP_PRIVATE_PATHS" ]   # a mismatch uses the answer up
  said_private "$HOME/One"
  run "$T/checks/private.sh" add "~/One/x/.."; [ "$status" -eq 2 ]
  run "$T/checks/private.sh" add "$HOME//One"; [ "$status" -eq 2 ]
  run "$T/checks/private.sh" add "~/One/"; [ "$status" -eq 0 ]
  [ "$(cat "$FORTKEEP_PRIVATE_PATHS")" = "$HOME/One" ]
}

@test "A21: /, the home folder, a folder above it and the fortkeep folder or one above it are only for the person to add" {
  account="$(/usr/bin/perl -e 'print +(getpwuid($<))[7]')"
  mkdir -p "$HOME/Projects"; ln -s "$HOME" "$HOME/Projects/home-link"
  for p in / "~/" "$HOME" "$(dirname "$HOME")" "$account" "$(dirname "$account")" "$T" "$T/" "$(dirname "$T")" \
    "$(printf '%s' "$HOME" | tr '[:lower:]' '[:upper:]')" "$HOME/Projects/home-link"; do
    said_private "$p"
    run "$T/checks/private.sh" add "$p"; [ "$status" -eq 4 ]; [[ "$output" == *"Terminal app"* ]]
  done
  [ ! -e "$FORTKEEP_PRIVATE_PATHS" ]
  run "$REPO/checks/ask.sh" private add "$HOME"; [ "$status" -eq 2 ]; [[ "$output" == *"Terminal app"* ]]
}

@test "A21: the same folders spelled through the data volume (/System/Volumes/Data) are refused too" {
  # The scanners compare private folders by their physical path (pwd -P), where /System/Volumes/Data/Users/u is /Users/u.
  d=/System/Volumes/Data; h="$d$(cd "$HOME" && pwd -P)"; t="$d$(cd "$T" && pwd -P)"
  [ -d "$h" ] && [ -d "$t" ]
  for p in "$h" "$h/" "$(dirname "$h")" "$t" "$d" /System/Volumes /System; do
    said_private "$p"
    run "$T/checks/private.sh" add "$p"; [ "$status" -eq 4 ]; [[ "$output" == *"Terminal app"* ]]
    run "$T/checks/ask.sh" private add "$p"; [ "$status" -eq 2 ]; [[ "$output" == *"Terminal app"* ]]
  done
  [ ! -e "$FORTKEEP_PRIVATE_PATHS" ]
  mkdir -p "$HOME/Private"
  run "$REPO/checks/ask.sh" private add "$h/Private"; [ "$status" -eq 0 ]   # a folder inside home is still asked about
}

@test "A21: the private-folder question names the exact folder it adds" {
  run "$REPO/checks/ask.sh" private add "~/Documents/Private/"; [ "$status" -eq 0 ]
  [[ "$(field question)" == *"\"$HOME/Documents/Private\""* ]]
  [ "$(jq -c '[.options[].label]' <<<"$output")" = '["Add private folder","Don'"'"'t add"]' ]
  run "$REPO/checks/ask.sh" private add; [ "$status" -eq 2 ]
  run "$REPO/checks/ask.sh" private add "Documents"; [ "$status" -eq 2 ]
}

@test "private.sh adds without printing the path" {
  said_private "$HOME/Hidden Folder"
  run "$T/checks/private.sh" add "~/Hidden Folder/"
  [ "$status" -eq 0 ]
  [[ "$output" != *Hidden* ]]
  [ "$(cat "$FORTKEEP_PRIVATE_PATHS")" = "$HOME/Hidden Folder" ]
  run "$T/checks/private.sh" count
  [ "$output" = "1 private path(s) configured" ]
}

@test "private.sh remove takes an entry off without printing it, and only for the person in a terminal app" {
  said_private "$HOME/One"; "$T/checks/private.sh" add "$HOME/One" >/dev/null
  said_private "$HOME/Two"; "$T/checks/private.sh" add "~/Two/" >/dev/null
  run "$T/checks/private.sh" remove "~/One/"; [ "$status" -eq 4 ]; [[ "$output" == *"run this yourself"* ]]
  [ "$(grep -c . "$FORTKEEP_PRIVATE_PATHS")" -eq 2 ]
  # The real script hard-codes /bin/ps; this test copy asks the fake one (a Terminal above this shell), on a pseudo-terminal.
  fake_ps
  sed -i '' "s#fortkeep_require_person /bin/ps#fortkeep_require_person $BATS_TEST_TMPDIR/bin/fakeps#" "$T/checks/private.sh"
  grep -q fakeps "$T/checks/private.sh"
  remove() { run script -q /dev/null "$T/checks/private.sh" remove "$1" </dev/null; }
  FAKE_COMM=claude remove "~/One/"; [ "$status" -eq 4 ]
  [ "$(grep -c . "$FORTKEEP_PRIVATE_PATHS")" -eq 2 ]
  remove "~/One/"
  [ "$status" -eq 0 ]; [[ "$output" == *"removed 1 private path(s) (1 total)"* ]]; [[ "$output" != *One* ]]
  remove "$HOME/Two"; [ "$status" -eq 0 ]
  remove "$HOME/Three"; [ "$status" -eq 1 ]; [[ "$output" != *Three* ]]
  [ "$(stat -f %Lp "$FORTKEEP_PRIVATE_PATHS")" = 600 ]
}

@test "diff shows status changes between runs" {
  "$T/checks/run.sh"
  sleep 1
  said_accept BL-OS-02 ok; "$T/checks/accept.sh" BL-OS-02 "ok"
  "$T/checks/run.sh"
  run "$T/checks/diff.sh"
  [[ "$output" == *"BL-OS-02: FAIL → ACCEPTED"* ]]
}

@test "diff with a single run says so" {
  "$T/checks/run.sh"
  run "$T/checks/diff.sh"
  [ "$output" = "no previous run to compare with" ]
}

@test "a check that reads stdin does not drop later controls" {
  "$T/checks/run.sh"
  [ "$(res BL-OS-05 status)" = PASS ]
  [ "$(res BL-OS-06 status)" = PASS ]
}

@test "missing controls file exits 2 and writes no latest" {
  FORTKEEP_CONTROLS=/nonexistent run "$T/checks/run.sh"
  [ "$status" -eq 2 ]
  [ ! -e "$FORTKEEP_REPORTS/latest" ]
}

@test "invalid config.json exits 2" {
  echo '{bad' > "$FORTKEEP_CONFIG"
  run "$T/checks/run.sh"
  [ "$status" -eq 2 ]
  [ ! -e "$FORTKEEP_REPORTS/latest" ]
}

@test "accepted.json that is not an object of objects exits 2 and writes no latest" {
  for bad in '[]' '"x"' '{"BL-OS-02":"str"}'; do
    printf '%s\n' "$bad" > "$FORTKEEP_ACCEPTED"
    run "$T/checks/run.sh"
    [ "$status" -eq 2 ]
    [ ! -e "$FORTKEEP_REPORTS/latest" ]
  done
}

@test "config overlays that are not a list of names exit 2" {
  for bad in '{"overlays":"tls-proxy"}' '{"overlays":[1]}'; do
    printf '%s\n' "$bad" > "$FORTKEEP_CONFIG"
    run "$T/checks/run.sh"
    [ "$status" -eq 2 ]
    [ ! -e "$FORTKEEP_REPORTS/latest" ]
  done
}

@test "a row that fails to merge makes the run incomplete: exit 1, no run folder, latest kept" {
  "$T/checks/run.sh"
  before="$(readlink "$FORTKEEP_REPORTS/latest")"
  sleep 1
  mk n7 'echo "{\"id\":\"7\",\"status\":\"FAIL\",\"evidence\":\"\",\"note\":\"\"}"'
  jq '. + [{"id":7,"title":"Num","layer":"baseline","level":"NICE","check":"checks/fake/n7.sh"}]' "$FORTKEEP_CONTROLS" > "$T/c.json"
  echo '{}' > "$FORTKEEP_ACCEPTED"
  FORTKEEP_CONTROLS="$T/c.json" run "$T/checks/run.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"run incomplete"* ]]
  [ "$(readlink "$FORTKEEP_REPORTS/latest")" = "$before" ]
  [ "$(ls -d "$FORTKEEP_REPORTS"/2*/ | wc -l)" -eq 1 ]
}

@test "a check cannot override the control's id, title, layer or level" {
  mk ok 'echo "{\"id\":\"BL-OS-01\",\"status\":\"PASS\",\"evidence\":\"e\",\"note\":\"\",\"title\":\"X\",\"level\":\"NICE\",\"layer\":\"gold\"}"'
  "$T/checks/run.sh"
  [ "$(res BL-OS-01 title)" = One ]
  [ "$(res BL-OS-01 level)" = MUST ]
  [ "$(res BL-OS-01 layer)" = baseline ]
}

@test "options without a value exit 2 instead of hanging" {
  run "$T/checks/run.sh" --only
  [ "$status" -eq 2 ]
  run "$T/checks/run.sh" --timeout
  [ "$status" -eq 2 ]
  run "$T/checks/configure.sh" --overlays
  [ "$status" -eq 2 ]
  run "$T/checks/configure.sh" --teach
  [ "$status" -eq 2 ]
}
@test "a weekly run triples each time limit and gives shell probes 30 s, unless the caller set them" {
  mk slow2 'sleep 3; echo "{\"id\":\"BL-OS-07\",\"status\":\"PASS\",\"evidence\":\"x\",\"note\":\"\"}"'
  mk st '. "$FORTKEEP_REPO/checks/lib/shells.sh"; echo "{\"id\":\"BL-OS-08\",\"status\":\"PASS\",\"evidence\":\"$FORTKEEP_SHELL_TIMEOUT\",\"note\":\"\"}"'
  echo '[{"id":"BL-OS-07","title":"S","layer":"baseline","level":"NICE","source":"§1","check":"checks/fake/slow2.sh","timeout":2},
         {"id":"BL-OS-08","title":"T","layer":"baseline","level":"NICE","source":"§1","check":"checks/fake/st.sh"}]' > "$FORTKEEP_CONTROLS"
  run "$T/checks/run.sh"; [ "$status" -eq 0 ]
  [ "$(res BL-OS-07 status)" = ERROR ]; [ "$(res BL-OS-08 evidence)" = 10 ]
  sleep 1; run "$T/checks/run.sh" --weekly; [ "$status" -eq 0 ]
  [ "$(res BL-OS-07 status)" = PASS ]; [ "$(res BL-OS-08 evidence)" = 30 ]
  sleep 1; FORTKEEP_SHELL_TIMEOUT=7 run "$T/checks/run.sh" --weekly; [ "$status" -eq 0 ]
  [ "$(res BL-OS-08 evidence)" = 7 ]
}

@test "progress goes to stderr, one line per check; stdout keeps only the summary and the report path" {
  "$T/checks/run.sh" > "$BATS_TEST_TMPDIR/out" 2> "$BATS_TEST_TMPDIR/err"
  [ "$(grep -c '^fortkeep: [0-9]*/6 BL-OS-0[1-6] ([0-9]*s so far)$' "$BATS_TEST_TMPDIR/err")" -eq 6 ]
  grep -q '^fortkeep: 1/6 BL-OS-01 (' "$BATS_TEST_TMPDIR/err"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/out" | tr -d ' ')" -eq 2 ]; grep -q '^report: reports/' "$BATS_TEST_TMPDIR/out"
  sleep 1; "$T/checks/run.sh" --only BL-OS-02 2> "$BATS_TEST_TMPDIR/err" >/dev/null
  [[ "$(cat "$BATS_TEST_TMPDIR/err")" =~ ^fortkeep:\ 1/1\ BL-OS-02\ \([0-9]+s\ so\ far\)$ ]]
}
@test "a check that a signal stops is an ERROR naming the security tools running here and asking for a narrow exclusion" {
  mk ok 'kill -KILL $$'
  stub systemextensionsctl 'printf "1 extension(s)\n--- com.apple.system_extension.endpoint_security\n*\t*\tX4MF6H9XZ6\tcom.crowdstrike.falcon.Agent (8.12/215.05)\tFalcon Sensor\t[activated enabled]\n"'
  run "$T/checks/run.sh"; [ "$status" -eq 0 ]
  [ "$(res BL-OS-01 status)" = ERROR ]
  ev="$(res BL-OS-01 evidence)"
  [[ "$ev" == "Something outside fortkeep stopped this check (signal KILL)"*"Falcon Sensor"* ]]
  [[ "$ev" == *"this one check"*"docs/security-tools.md"*"not the whole fortkeep folder"*"never turn it off."* ]]
  [[ "$(res BL-OS-03 evidence)" == *"timed out"* ]]
  # No security tool found: the same advice, naming none
  stub systemextensionsctl 'printf "0 extension(s)\n"'
  sleep 1; run "$T/checks/run.sh"; [ "$status" -eq 0 ]
  ev="$(res BL-OS-01 evidence)"
  [[ "$ev" == "Something outside fortkeep stopped this check (signal KILL). "*"docs/security-tools.md"* ]]
  [[ "$ev" != *"running on this Mac"* ]]
}

@test "a fake command earlier on the caller's PATH, an exported function or BASH_ENV can't answer for a system tool" {
  mkdir -p "$T/checks/macos" "$BATS_TEST_TMPDIR/evil"; cp "$REPO/checks/macos/BL-OS-01.sh" "$T/checks/macos/"
  echo '[{"id":"BL-OS-01","title":"FV","layer":"baseline","level":"MUST","source":"§1","check":"checks/macos/BL-OS-01.sh"}]' > "$FORTKEEP_CONTROLS"
  stub fdesetup 'echo false'   # the system's answer
  printf '#!/bin/sh\necho true\n' > "$BATS_TEST_TMPDIR/evil/fdesetup"; chmod +x "$BATS_TEST_TMPDIR/evil/fdesetup"
  PATH="$BATS_TEST_TMPDIR/evil:$PATH" run "$T/checks/run.sh"; [ "$status" -eq 0 ]; [ "$(res BL-OS-01 status)" = FAIL ]
  printf 'fdesetup() { echo true; }\nexport -f fdesetup\n' > "$BATS_TEST_TMPDIR/env.sh"
  sleep 1; run /bin/bash -c '. "$1"; "$2"' _ "$BATS_TEST_TMPDIR/env.sh" "$T/checks/run.sh"; [ "$status" -eq 0 ]
  [ "$(res BL-OS-01 status)" = FAIL ]
  sleep 1; run /bin/bash -c '. "$1"; /bin/bash "$2"' _ "$BATS_TEST_TMPDIR/env.sh" "$T/checks/run.sh"; [ "$status" -eq 0 ]
  [ "$(res BL-OS-01 status)" = FAIL ]
  sleep 1; BASH_ENV="$BATS_TEST_TMPDIR/env.sh" run /bin/bash "$T/checks/run.sh"; [ "$status" -eq 0 ]
  [ "$(res BL-OS-01 status)" = FAIL ]
}

@test "outside the test suite no FORTKEEP_* setting or other HOME reaches a check, and one variable can't fake the suite" {
  mk ok 'echo "{\"id\":\"BL-OS-01\",\"status\":\"PASS\",\"evidence\":\"${FORTKEEP_SYSROOT-unset} ${FORTKEEP_WEEKLY_RUN-unset} $HOME\",\"note\":\"\"}"'
  echo '[{"id":"BL-OS-01","title":"One","layer":"baseline","level":"MUST","source":"§1","check":"checks/fake/ok.sh"}]' > "$FORTKEEP_CONTROLS"
  mkdir -p "$T/controls"; cp "$FORTKEEP_CONTROLS" "$T/controls/controls.json"   # where a real run reads them
  out() { jq -r '.results[0].evidence' "$1/latest/results.json"; }
  FORTKEEP_WEEKLY_RUN=1 run "$T/checks/run.sh"; [ "$status" -eq 0 ]
  [ "$(out "$FORTKEEP_REPORTS")" = "$FORTKEEP_SYSROOT 1 $HOME" ]                # the suite: honoured
  rm "$BATS_TEST_TMPDIR/.fortkeep-test"                                         # a person's Mac
  FORTKEEP_WEEKLY_RUN=1 run "$T/checks/run.sh"; [ "$status" -eq 0 ]
  read -r s w h <<<"$(out "$T/reports")"
  [ "$s" = unset ]; [ "$w" = unset ]; [ -n "$h" ]; [ "$h" != "$HOME" ]
  sleep 1; run "$T/checks/run.sh" --weekly; [ "$status" -eq 0 ]
  read -r s w h <<<"$(out "$T/reports")"; [ "$w" = 1 ]
  : > "$BATS_TEST_TMPDIR/.fortkeep-test"; mkdir -p "$BATS_TEST_TMPDIR-elsewhere"  # the marker, but HOME outside it
  sleep 1; HOME="$BATS_TEST_TMPDIR-elsewhere" run "$T/checks/run.sh"; [ "$status" -eq 0 ]
  read -r s w h <<<"$(out "$T/reports")"
  [ "$s" = unset ]; [ "$h" != "$BATS_TEST_TMPDIR-elsewhere" ]
  rmdir "$BATS_TEST_TMPDIR-elsewhere"
  # The folder itself as HOME: still a person's Mac, so this run lands in the repo's own reports/.
  prev="$(readlink "$T/reports/latest")"
  sleep 1; HOME="$BATS_TEST_TMPDIR" run "$T/checks/run.sh"; [ "$status" -eq 0 ]
  [ "$(readlink "$T/reports/latest")" != "$prev" ]
  read -r s w h <<<"$(out "$T/reports")"; [ "$s" = unset ]; [ "$h" != "$BATS_TEST_TMPDIR" ]
}

@test "a value that looks like an exported function's name doesn't make run.sh start again for ever" {
  X=$'x\nBASH_FUNC_z%%=() { :; }' run /bin/bash -c '. "$1/checks/lib/common.sh"; fortkeep_timeout 30 "$2"' _ "$REPO" "$T/checks/run.sh"
  [ "$status" -eq 0 ]; [ "$(res BL-OS-01 status)" = PASS ]
}
