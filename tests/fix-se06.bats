load helpers

setup() {
  setup_env; fix_tree
  REAL_GIT="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v git)"
  stub git "[ \"\$1\" = --version ] && { echo \"git version \${FAKE_GIT_VERSION:-2.56.0}\"; exit 0; }; exec '$REAL_GIT' \"\$@\""
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zlogin"
}
fix() { run /bin/bash "$T/fixes/macos/BL-SE-06.sh" "$1"; }
approve() { date +%s > "$FORTKEEP_REPORTS/.approvals/BL-SE-06.$1"; }

@test "refuses without approval" { fix apply; [ "$status" -eq 4 ]; }
@test "MANUAL when gitleaks isn't installed" {
  approve apply; fix apply; [ "$status" -eq 3 ]; [[ "$output" == *"brew install gitleaks"* ]]
  [ ! -e "$HOME/.gitconfig" ]
}
@test "apply adds the hook with gitleaks' full path, the check passes, undo removes it" {
  stub gitleaks 'exit 0'
  approve apply; fix apply; [ "$status" -eq 0 ]
  [ "$(git config --global --get hook.fortkeep-gitleaks.command)" = "'$BATS_TEST_TMPDIR/bin/gitleaks' git --pre-commit --staged --redact --no-banner" ]
  [ "$(/bin/bash "$REPO/checks/macos/BL-SE-06.sh" | jq -r .status)" = PASS ]
  grep -q '| BL-SE-06 | apply |' "$FORTKEEP_REPORTS/change-log.md"
  approve apply; fix apply; [[ "$output" == *"nothing to change"* ]]
  approve undo; fix undo; [ "$status" -eq 0 ]; [ ! -e "$HOME/.gitconfig" ]
}
@test "apply quotes gitleaks' path, so a home and a gitleaks folder with spaces still run it on commit" {
  export HOME="$BATS_TEST_TMPDIR/my home"; mkdir -p "$HOME"; dev_marker
  GL="$BATS_TEST_TMPDIR/my tools"; mkdir -p "$GL"
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" > "$GL/gitleaks"; chmod +x "$GL/gitleaks"
  printf 'export PATH="%s:%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$GL" "$BATS_TEST_TMPDIR/bin" > "$HOME/.zlogin"
  approve apply; fix apply; [ "$status" -eq 0 ]
  [ "$(/bin/bash "$REPO/checks/macos/BL-SE-06.sh" | jq -r .status)" = PASS ]
  r="$BATS_TEST_TMPDIR/r"; git init -q "$r"; echo a > "$r/a"; git -C "$r" add a
  git -C "$r" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm x
  [ -e "$BATS_TEST_TMPDIR/ran" ]
}
@test "MANUAL when GIT_CONFIG_GLOBAL is set, before any backup or change" {
  stub gitleaks 'exit 0'
  ALT="$BATS_TEST_TMPDIR/alt-git-config"
  approve apply; GIT_CONFIG_GLOBAL="$ALT" fix apply; [ "$status" -eq 3 ]
  [[ "$output" == *GIT_CONFIG_GLOBAL* ]]
  [ ! -e "$ALT" ]; [ ! -e "$HOME/.gitconfig" ]
  [ -z "$(ls "$FORTKEEP_BACKUPS/BL-SE-06" 2>/dev/null)" ]
}
@test "MANUAL on a git older than 2.54, nothing changed" {
  stub gitleaks 'exit 0'
  approve apply; FAKE_GIT_VERSION=2.50.1 fix apply; [ "$status" -eq 3 ]
  [ ! -e "$HOME/.gitconfig" ]
}
@test "a dangling ~/.gitconfig link stops the fix and nothing is changed" {
  stub gitleaks 'exit 0'
  ln -s "$HOME/nowhere" "$HOME/.gitconfig"
  approve apply; fix apply; [ "$status" -eq 3 ]
  [[ "$output" == *"nothing was changed"* ]]
  [ -L "$HOME/.gitconfig" ]; [ ! -e "$HOME/.gitconfig" ]
  [ -z "$(find "$FORTKEEP_BACKUPS" -name manifest.tsv 2>/dev/null)" ]
  approve undo; fix undo; [ "$status" -eq 5 ]
}
@test "undo removes only the gitleaks hook and keeps git config edits made after apply" {
  stub gitleaks 'exit 0'
  approve apply; fix apply; [ "$status" -eq 0 ]
  [ -n "$(find "$FORTKEEP_BACKUPS/BL-SE-06" -name sealed.tsv)" ]
  git config --global user.name Later
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(git config --global user.name)" = Later ]
  run git config --global --get hook.fortkeep-gitleaks.command; [ "$status" -ne 0 ]
}
@test "a git config that can't be edited on undo reports undo incomplete and keeps the backup" {
  stub gitleaks 'exit 0'
  approve apply; fix apply; [ "$status" -eq 0 ]
  stub git "for a; do [ \"\$a\" = --remove-section ] && exit 1; done; exec '$REAL_GIT' \"\$@\""
  approve undo; fix undo; [ "$status" -eq 6 ]; [[ "$output" == *"undo incomplete"* ]]
  [ -n "$(find "$FORTKEEP_BACKUPS/BL-SE-06" -name manifest.tsv)" ]
}
@test "undo removes the hook apply wrote to the XDG git config even after a ~/.gitconfig appears" {
  stub gitleaks 'exit 0'
  X="$HOME/.config/git/config"; mkdir -p "$(dirname "$X")"; : > "$X"
  approve apply; fix apply; [ "$status" -eq 0 ]
  git config --file "$X" --get hook.fortkeep-gitleaks.command >/dev/null
  printf '[user]\n\tname = Later\n' > "$HOME/.gitconfig"
  approve undo; fix undo; [ "$status" -eq 0 ]
  run git config --file "$X" --get-regexp '^hook\.fortkeep-'; [ "$status" -eq 1 ]
  [ "$(git config --file "$HOME/.gitconfig" user.name)" = Later ]
}
