load helpers

setup() {
  setup_env
  fix_tree
  U="$HOME/Library/Application Support/Code/User"
  mkdir -p "$U/profiles/p1"
  echo '{"editor.fontSize":14}' > "$U/settings.json"
  echo '{}' > "$U/profiles/p1/settings.json"
}
fix() { run /bin/bash "$T/fixes/macos/BL-RC-01.sh" "$1"; }
approve() { date +%s > "$FORTKEEP_REPORTS/.approvals/BL-RC-01.$1"; }

@test "refuses without approval" {
  fix apply; [ "$status" -eq 4 ]; [[ "$output" == *REFUSED* ]]
  [ "$(jq -r '."task.allowAutomaticTasks" // "unset"' "$U/settings.json")" = unset ]
}
@test "refuses an expired approval and consumes it" {
  approve apply; touch -t 202001010000 "$FORTKEEP_REPORTS/.approvals/BL-RC-01.apply"
  fix apply; [ "$status" -eq 4 ]; [[ "$output" == *expired* ]]
  [ ! -e "$FORTKEEP_REPORTS/.approvals/BL-RC-01.apply" ]
}
@test "refuses a future-dated approval as expired and consumes it" {
  approve apply; touch -t 203001010000 "$FORTKEEP_REPORTS/.approvals/BL-RC-01.apply"
  fix apply; [ "$status" -eq 4 ]; [[ "$output" == *expired* ]]
  [ ! -e "$FORTKEEP_REPORTS/.approvals/BL-RC-01.apply" ]
  [ "$(jq -r '."task.allowAutomaticTasks" // "unset"' "$U/settings.json")" = unset ]
}
@test "a token that vanishes while it is being checked refuses, and never lets the caller's next command run" {
  # A second run consuming the same token can remove it between the existence test and the mtime read; the DEBUG trap
  # does that deterministically. bash 3.2 abandons a whole top-level command on an arithmetic error, || exit 4 included.
  D="$BATS_TEST_TMPDIR/approvals"; mkdir -p "$D"; touch -t 202001010000 "$D/BL-XX-01.apply"
  cat > "$BATS_TEST_TMPDIR/harness.sh" <<EOF
. "$REPO/checks/lib/approval.sh"
req() { fortkeep_take_approval "$D" BL-XX-01 apply || exit 4; }
set -T; trap '[[ \$BASH_COMMAND == *stat* ]] && /bin/rm -f "$D"/BL-XX-01.apply*' DEBUG
req
trap - DEBUG
echo RAN
EOF
  run /usr/bin/env -i /bin/bash -p "$BATS_TEST_TMPDIR/harness.sh"
  [ "$status" -eq 4 ]; [[ "$output" != *RAN* ]]
}
@test "two runs never both pass one fresh token" {
  D="$BATS_TEST_TMPDIR/approvals"; mkdir -p "$D"; date +%s > "$D/BL-XX-01.apply"
  cat > "$BATS_TEST_TMPDIR/harness.sh" <<EOF
. "$REPO/checks/lib/approval.sh"
# The second consumer runs in full just before the first removes the token.
set -T; trap '[[ \$BASH_COMMAND == */bin/rm* ]] && [ -z "\$second" ] && { second=1; fortkeep_take_approval "$D" BL-XX-01 apply && echo SECOND; }' DEBUG
fortkeep_take_approval "$D" BL-XX-01 apply && echo FIRST
EOF
  run /usr/bin/env -i /bin/bash -p "$BATS_TEST_TMPDIR/harness.sh"
  [ "$(grep -c -e FIRST -e SECOND <<<"$output")" -eq 1 ]
  [ -z "$(ls -A "$D")" ]
}
@test "checks the approval before loading any other helper" {
  printf 'touch "%s"\n' "$BATS_TEST_TMPDIR/sourced" > "$T/checks/lib/editors.sh"
  fix apply
  [ "$status" -eq 4 ]
  [ ! -e "$BATS_TEST_TMPDIR/sourced" ]
}
@test "the environment cannot redirect approvals, the token lifetime or PATH" {
  E="$BATS_TEST_TMPDIR/evil"; mkdir -p "$E/.approvals" "$E/bin"
  date +%s > "$E/.approvals/BL-RC-01.apply"
  approve apply; touch -t 202001010000 "$FORTKEEP_REPORTS/.approvals/BL-RC-01.apply"
  printf '#!/bin/bash\necho $(( $(date +%%s) - 100 ))\n' > "$E/bin/stat"; chmod +x "$E/bin/stat"
  run env FORTKEEP_REPORTS="$E" FORTKEEP_REPO="$E" FX_TOKEN_TTL=999999999 PATH="$E/bin:$PATH" \
    /bin/bash "$T/fixes/macos/BL-RC-01.sh" apply
  [ "$status" -eq 4 ]; [[ "$output" == *expired* ]]
  [ -e "$E/.approvals/BL-RC-01.apply" ]
  [ "$(jq -r '."task.allowAutomaticTasks" // "unset"' "$U/settings.json")" = unset ]
}
@test "an old token stays expired whatever lifetime the environment asks for" {
  approve apply; touch -t 202001010000 "$FORTKEEP_REPORTS/.approvals/BL-RC-01.apply"
  run env FX_TOKEN_TTL=999999999 /bin/bash "$T/fixes/macos/BL-RC-01.sh" apply
  [ "$status" -eq 4 ]; [[ "$output" == *expired* ]]
}
@test "apply's message and change-log row name every editor it edits, not just VS Code and Cursor" {
  approve apply
  fix apply; [ "$status" -eq 0 ]
  for e in "VS Code" Insiders Cursor Windsurf VSCodium; do
    [[ "$output" == *"$e"* ]]; grep '| BL-RC-01 | apply |' "$FORTKEEP_REPORTS/change-log.md" | grep -q "$e"
  done
}
@test "apply sets off everywhere, keeps other settings, consumes the token, logs" {
  approve apply
  fix apply; [ "$status" -eq 0 ]
  [ "$(jq -r '."task.allowAutomaticTasks"' "$U/settings.json")" = off ]
  [ "$(jq -r '."editor.fontSize"' "$U/settings.json")" = 14 ]
  [ "$(jq -r '."task.allowAutomaticTasks"' "$U/profiles/p1/settings.json")" = off ]
  [ ! -e "$FORTKEEP_REPORTS/.approvals/BL-RC-01.apply" ]
  grep -q '| BL-RC-01 | apply |' "$FORTKEEP_REPORTS/change-log.md"
  run /bin/bash "$REPO/checks/macos/BL-RC-01.sh"; [ "$(field status)" = PASS ]
}
@test "undo restores the originals and needs its own approval" {
  approve apply; fix apply
  fix undo; [ "$status" -eq 4 ]
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(cat "$U/settings.json")" = '{"editor.fontSize":14}' ]
  [ "$(cat "$U/profiles/p1/settings.json")" = '{}' ]
}
@test "a missing settings file is created, and removed again on undo" {
  rm "$U/settings.json"
  approve apply; fix apply
  [ "$(jq -r '."task.allowAutomaticTasks"' "$U/settings.json")" = off ]
  approve undo; fix undo
  [ ! -e "$U/settings.json" ]
}
@test "settings with comments are left alone and reported as manual" {
  printf '{\n  // mine\n  "a": 1\n}\n' > "$U/settings.json"
  before="$(cat "$U/settings.json")"
  approve apply; fix apply
  [ "$status" -eq 3 ]; [[ "$output" == *MANUAL* ]]
  [ "$(cat "$U/settings.json")" = "$before" ]
}
@test "undo with nothing to undo" {
  approve undo; fix undo; [ "$status" -eq 5 ]
}
@test "bad action" {
  fix explode; [ "$status" -eq 2 ]
}
@test "apply twice then undo restores the originals" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  approve apply; fix apply; [ "$status" -eq 0 ]; [[ "$output" == *"nothing to change"* ]]
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(cat "$U/settings.json")" = '{"editor.fontSize":14}' ]
  [ "$(cat "$U/profiles/p1/settings.json")" = '{}' ]
}
@test "a non-object JSON file is left alone and reported as manual" {
  echo '[]' > "$U/settings.json"
  approve apply; fix apply
  [ "$status" -eq 3 ]; [[ "$output" == *MANUAL* ]]
  [ "$(cat "$U/settings.json")" = '[]' ]
}
@test "all-manual run logs nothing and leaves nothing to undo" {
  rm -r "$U/profiles"
  printf '{\n  // mine\n  "a": 1\n}\n' > "$U/settings.json"
  approve apply; fix apply; [ "$status" -eq 3 ]
  [ ! -e "$FORTKEEP_REPORTS/change-log.md" ]
  approve undo; fix undo; [ "$status" -eq 5 ]
}
@test "a failed restore keeps the backup, exits 6, and does not claim restored" {
  approve apply; fix apply
  chmod 444 "$U/settings.json"
  approve undo; fix undo
  chmod 644 "$U/settings.json"
  [ "$status" -eq 6 ]; [[ "$output" == *"could not restore"* ]]; [[ "$output" != *"restored"* ]]
  run grep -q '| undo |' "$FORTKEEP_REPORTS/change-log.md"; [ "$status" -ne 0 ]
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(cat "$U/settings.json")" = '{"editor.fontSize":14}' ]
}
@test "a failed write in a later apply does not displace the earlier backup" {
  mv "$U/profiles" "$U/profiles.off"
  approve apply; fix apply; [ "$status" -eq 0 ]
  mv "$U/profiles.off" "$U/profiles"; chmod 444 "$U/profiles/p1/settings.json"
  rows="$(wc -l < "$FORTKEEP_REPORTS/change-log.md")"
  approve apply; fix apply
  chmod 644 "$U/profiles/p1/settings.json"
  [ "$status" -eq 3 ]; [[ "$output" == *MANUAL* ]]
  [ "$(wc -l < "$FORTKEEP_REPORTS/change-log.md")" -eq "$rows" ]
  [ "$(ls "$FORTKEEP_BACKUPS/BL-RC-01" | wc -l)" -eq 1 ]
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(cat "$U/settings.json")" = '{"editor.fontSize":14}' ]
}
@test "a settings file that can't be backed up (dangling link) is left alone and reported as manual" {
  mkdir "$HOME/elsewhere"; rm "$U/settings.json"; ln -s "$HOME/elsewhere/target" "$U/settings.json"
  approve apply; fix apply
  [ "$status" -eq 3 ]; [[ "$output" == *MANUAL* ]]; [[ "$output" == *"Code/User/settings.json"* ]]
  [ -L "$U/settings.json" ]; [ ! -e "$HOME/elsewhere/target" ]
  [ "$(jq -r '."task.allowAutomaticTasks"' "$U/profiles/p1/settings.json")" = off ]
}
@test "apply records the post-fix state; undo with no later edit restores as before" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  [ -f "$(ls -d "$FORTKEEP_BACKUPS"/BL-RC-01/*/)sealed.tsv" ]
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(cat "$U/settings.json")" = '{"editor.fontSize":14}' ]
  [ "$(cat "$U/profiles/p1/settings.json")" = '{}' ]
}
@test "undo stops with exit 6 and changes nothing when a file was edited after apply" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  jq '. + {"editor.tabSize": 2}' "$U/settings.json" > "$U/s"; mv "$U/s" "$U/settings.json"
  edited="$(cat "$U/settings.json")"
  approve undo; fix undo
  [ "$status" -eq 6 ]; [[ "$output" == *"undo stopped"* ]]; [[ "$output" == *"~/Library/Application Support/Code/User/settings.json"* ]]
  [[ "$output" == *"backup kept in ~/.local/state/fortkeep/backups/BL-RC-01/"* ]]
  [ "$(cat "$U/settings.json")" = "$edited" ]
  [ "$(jq -r '."task.allowAutomaticTasks"' "$U/profiles/p1/settings.json")" = off ]
  run grep -q '| undo |' "$FORTKEEP_REPORTS/change-log.md"; [ "$status" -ne 0 ]
}
@test "a backup made before sealing existed restores as before" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  rm "$FORTKEEP_BACKUPS"/BL-RC-01/*/sealed.tsv
  echo '{"other":1}' > "$U/settings.json"
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(cat "$U/settings.json")" = '{"editor.fontSize":14}' ]
}
@test "a partly manual apply still records the post-fix state" {
  printf '{\n  // mine\n  "a": 1\n}\n' > "$U/settings.json"
  approve apply; fix apply; [ "$status" -eq 3 ]
  [ -f "$(ls -d "$FORTKEEP_BACKUPS"/BL-RC-01/*/)sealed.tsv" ]
}
@test "a fix run directly ignores BASH_ENV and passes no FORTKEEP_* setting or BASH_ENV to the checks it runs" {
  printf '#!/bin/bash\nenv | grep -oE "^(FORTKEEP_[A-Z_]+|BASH_ENV|ENV|CDPATH)=" | tr -d = > "%s/seen"\necho "{\\"status\\":\\"PASS\\"}"\n' "$BATS_TEST_TMPDIR" > "$T/checks/macos/BL-RC-02.sh"
  printf 'touch "%s/sourced"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/benv.sh"
  date +%s > "$FORTKEEP_REPORTS/.approvals/BL-RC-02.apply"
  run env BASH_ENV="$BATS_TEST_TMPDIR/benv.sh" ENV="$BATS_TEST_TMPDIR/benv.sh" CDPATH=/tmp FORTKEEP_SHELL_TIMEOUT=1 FORTKEEP_CLAUDE_DIRS=/x \
    "$T/fixes/macos/BL-RC-02.sh" apply
  [ "$status" -eq 0 ]; [[ "$output" == *"nothing to change"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/sourced" ]
  run grep -E '^(FORTKEEP_SHELL_TIMEOUT|FORTKEEP_CLAUDE_DIRS|BASH_ENV|ENV|CDPATH)$' "$BATS_TEST_TMPDIR/seen"; [ "$status" -eq 1 ]
  grep -q '^FORTKEEP_REPO$' "$BATS_TEST_TMPDIR/seen"
}
@test "a caller's exported function can't spoof the check a fix runs to verify itself" {
  printf '#!/bin/bash\n[ "$(type -t jq)" = function ] && touch "%s/fn-seen"\necho "{\\"status\\":\\"PASS\\"}"\n' "$BATS_TEST_TMPDIR" > "$T/checks/macos/BL-RC-02.sh"
  date +%s > "$FORTKEEP_REPORTS/.approvals/BL-RC-02.apply"
  jq() { echo '{"status":"PASS"}'; }; export -f jq
  [ "$(/bin/bash -c 'type -t jq')" = function ]   # the export really reaches a plain /bin/bash
  run "$T/fixes/macos/BL-RC-02.sh" apply
  unset -f jq
  [ "$status" -eq 0 ]; [[ "$output" == *"nothing to change"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/fn-seen" ]
}
@test "every fix runs its checks with bash -p" {
  run grep -nE '/bin/bash "\$' "$REPO"/fixes/macos/*.sh "$REPO"/fixes/lib/fix.sh; [ "$status" -eq 1 ]
  grep -q '/bin/bash -p "\$FORTKEEP_REPO/checks/macos/' "$REPO/fixes/macos/BL-RC-02.sh"
}
@test "every fix script and fix.sh start with #!/bin/bash -p" {
  for f in "$REPO"/fixes/lib/fix.sh "$REPO"/fixes/macos/*.sh; do [ "$(head -1 "$f")" = '#!/bin/bash -p' ] || { echo "$f"; false; }; done
}
