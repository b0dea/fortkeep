load helpers

setup() {
  setup_env
  fix_tree
  mkdir -p "$HOME/.safe-chain/shims" "$HOME/.safe-chain/bin"
  printf '#!/bin/sh\necho OK\n' > "$HOME/.safe-chain/shims/npm"; chmod +x "$HOME/.safe-chain/shims/npm"
}
fix() { run /bin/bash "$T/fixes/macos/BL-SC-02.sh" "$1"; }
approve() { date +%s > "$DEVWARD_REPORTS/.approvals/BL-SC-02.$1"; }
status_of() { /bin/bash "$REPO/checks/macos/$1.sh" | jq -r .status; }

@test "refuses without approval and changes nothing" {
  fix apply; [ "$status" -eq 4 ]
  [ ! -e "$HOME/.zshenv" ]
}
@test "MANUAL when Safe Chain isn't installed" {
  rm -r "$HOME/.safe-chain"
  approve apply; fix apply; [ "$status" -eq 3 ]; [[ "$output" == *"BL-SC-01"* ]]
  [ ! -e "$HOME/.zshenv" ]
}
@test "apply on a fresh home makes BL-SC-02 and BL-SC-04 pass, logs, and undo removes everything" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  [ "$(status_of BL-SC-02)" = PASS ]; [ "$(status_of BL-SC-04)" = PASS ]
  grep -q '| BL-SC-02 | apply |' "$DEVWARD_REPORTS/change-log.md"
  [ -n "$(find "$DEVWARD_BACKUPS/BL-SC-02" -name sealed.tsv)" ]
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ ! -e "$HOME/.zshenv" ]; [ ! -e "$HOME/.zshrc" ]; [ ! -e "$HOME/.zlogin" ]
  [ ! -e "$HOME/.config/devward/path-front.sh" ]
}
@test "existing start-up files keep their content and get the line once" {
  printf 'alias ll="ls -l"\n' > "$HOME/.zshrc"
  approve apply; fix apply; [ "$status" -eq 0 ]
  approve apply; fix apply; [ "$status" -eq 0 ]; [[ "$output" == *"nothing to change"* ]]
  [ "$(grep -c 'devward BL-SC-02' "$HOME/.zshrc")" -eq 1 ]
  head -1 "$HOME/.zshrc" | grep -q 'alias ll'
  approve undo; fix undo
  [ "$(cat "$HOME/.zshrc")" = 'alias ll="ls -l"' ]
}
@test "bash start-up files get the line only if they exist" {
  touch "$HOME/.bashrc" "$HOME/.bash_profile"
  approve apply; fix apply; [ "$status" -eq 0 ]
  grep -q 'devward BL-SC-02' "$HOME/.bash_profile"
  [ ! -e "$HOME/.profile" ]
  [ "$(status_of BL-SC-02)" = PASS ]
}
@test "a lower age gate is raised to 168, a higher one is kept" {
  echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=24' > "$HOME/.zshenv"
  approve apply; fix apply
  [ "$(/bin/zsh -c 'echo $SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS')" = 168 ]
  approve undo; fix undo
  echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=200' > "$HOME/.zshenv"
  approve apply; fix apply
  [ "$(/bin/zsh -c 'echo $SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS')" = 200 ]
}
@test "the path-front file keeps PATH entries in order and removes duplicates of the shims" {
  mkdir -p "$HOME/.config/devward"; cp "$REPO/fixes/files/path-front.sh" "$HOME/.config/devward/"
  out="$(PATH="/a:$HOME/.safe-chain/shims:/b" /bin/zsh -fc ". $HOME/.config/devward/path-front.sh; echo \$PATH")"
  [ "$out" = "$HOME/.safe-chain/shims:$HOME/.safe-chain/bin:/a:/b" ]
  out="$(PATH="/a:/b" /bin/bash -c ". $HOME/.config/devward/path-front.sh; . $HOME/.config/devward/path-front.sh; echo \$PATH")"
  [ "$out" = "$HOME/.safe-chain/shims:$HOME/.safe-chain/bin:/a:/b" ]
}
@test "a dangling symlink start-up file is refused as MANUAL and left alone" {
  mkdir "$HOME/elsewhere"; ln -s "$HOME/elsewhere/target" "$HOME/.zshrc"
  approve apply; fix apply; [ "$status" -eq 3 ]; [[ "$output" == *".zshrc"* ]]
  [ -L "$HOME/.zshrc" ]; [ ! -e "$HOME/elsewhere/target" ]
}
@test "a backup that cannot be made stops with MANUAL before any file is changed" {
  B="$(dirname "$DEVWARD_BACKUPS")"; mkdir -p "$B"
  approve apply; chmod 500 "$B"
  fix apply; chmod 700 "$B"
  [ "$status" -eq 3 ]; [[ "$output" == *"back up"* ]]
  [ ! -e "$HOME/.zshenv" ]; [ ! -e "$HOME/.config/devward/path-front.sh" ]
}
@test "a symlink to a real file gets the line in the target and undo restores it" {
  printf 'alias ll="ls -l"\n' > "$HOME/real-rc"; ln -s "$HOME/real-rc" "$HOME/.zshrc"
  approve apply; fix apply; [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]; grep -q 'devward BL-SC-02' "$HOME/real-rc"
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]; [ "$(cat "$HOME/real-rc")" = 'alias ll="ls -l"' ]
}

@test "fx_latest_backup picks the newest folder not yet undone" {
  . "$T/fixes/lib/fix.sh"
  mkdir -p "$DEVWARD_BACKUPS/X/20260101T000000Z-1" "$DEVWARD_BACKUPS/X/20260102T000000Z-1"
  touch "$DEVWARD_BACKUPS/X/20260101T000000Z-1/manifest.tsv" "$DEVWARD_BACKUPS/X/20260102T000000Z-1/manifest.restored.tsv"
  [ "$(fx_latest_backup X)" = "$DEVWARD_BACKUPS/X/20260101T000000Z-1" ]
  run fx_latest_backup Y; [ "$status" -eq 1 ]
}
@test "undo removes only the marked line and keeps edits made after apply" {
  printf 'alias ll="ls -l"\n' > "$HOME/.zshrc"
  approve apply; fix apply; [ "$status" -eq 0 ]
  printf 'alias gs="git status"\n' >> "$HOME/.zshrc"
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.zshrc")" = "$(printf 'alias ll="ls -l"\nalias gs="git status"')" ]
  [ ! -e "$HOME/.zshenv" ]; [ ! -e "$HOME/.config/devward/path-front.sh" ]
  grep -q '| BL-SC-02 | undo |' "$DEVWARD_REPORTS/change-log.md"
}
@test "undo removes the marked line from between two others without joining them" {
  printf 'export A=1\n' > "$HOME/.zshrc"
  approve apply; fix apply; [ "$status" -eq 0 ]
  printf 'export A=1\n%s\nexport B=2\n' "$(grep -F 'devward BL-SC-02' "$HOME/.zshrc")" > "$HOME/.zshrc"
  approve undo; fix undo; [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.zshrc")" = "$(printf 'export A=1\nexport B=2')" ]
}
@test "undo leaves an edited PATH file alone, says why, and still removes the lines" {
  approve apply; fix apply; [ "$status" -eq 0 ]
  echo '# mine' >> "$HOME/.config/devward/path-front.sh"
  approve undo; fix undo; [ "$status" -eq 6 ]; [[ "$output" == *"your later edits stopped the undo"* ]]
  grep -q '# mine' "$HOME/.config/devward/path-front.sh"
  [ ! -e "$HOME/.zshenv" ]
  approve undo; fix undo; [ "$status" -eq 5 ]
}
@test "a failed line removal leaves the start-up file as it was and reports undo incomplete" {
  printf 'alias ll="ls -l"\n' > "$HOME/.zshrc"
  approve apply; fix apply; [ "$status" -eq 0 ]
  before="$(shasum -a 256 < "$HOME/.zshrc")"
  stub perl 'printf partial; exit 1'
  approve undo; fix undo; [ "$status" -eq 6 ]; [[ "$output" == *"undo incomplete"* ]]
  [ "$(shasum -a 256 < "$HOME/.zshrc")" = "$before" ]
  [ -f "$HOME/.config/devward/path-front.sh" ]
}
@test "an unreadable start-up file is never written by undo" {
  [ "$(id -u)" -ne 0 ] || skip "root can read any file"
  printf 'alias ll="ls -l"\n' > "$HOME/.zshrc"
  approve apply; fix apply; [ "$status" -eq 0 ]
  cp "$HOME/.zshrc" "$BATS_TEST_TMPDIR/before"; chmod 200 "$HOME/.zshrc"
  approve undo; fix undo; s="$status"; chmod 600 "$HOME/.zshrc"
  [ "$s" -eq 6 ]; [[ "$output" == *"undo incomplete"* ]]
  cmp -s "$HOME/.zshrc" "$BATS_TEST_TMPDIR/before"
}
@test "fx_unchanged, fx_restore_file, fx_was_absent and fx_drop_blank_created act on one file each" {
  . "$T/fixes/lib/fix.sh"
  printf 'old\n' > "$HOME/a"; B="$DEVWARD_BACKUPS/X/$FX_STAMP"
  { fx_backup X "$HOME/a"; fx_backup X "$HOME/b"; fx_backup X "$HOME/c"; } || :  # its grep -c trips bats' errexit
  [ "$(grep -c . "$B/manifest.tsv")" -eq 3 ]
  printf 'new\n' > "$HOME/a"; printf ' \n\n' > "$HOME/b"; printf 'kept\n' > "$HOME/c"; fx_seal X
  fx_unchanged "$B" "$HOME/a"; fx_unchanged "$B" "$HOME/elsewhere"
  echo edit >> "$HOME/a"; run fx_unchanged "$B" "$HOME/a"; [ "$status" -eq 1 ]
  fx_was_absent "$B" "$HOME/b"; run fx_was_absent "$B" "$HOME/a"; [ "$status" -eq 1 ]
  fx_restore_file "$B" "$HOME/a"; [ "$(cat "$HOME/a")" = old ]
  run fx_restore_file "$B" "$HOME/elsewhere"; [ "$status" -eq 1 ]
  printf 'x\n' > "$HOME/a"; fx_drop_blank_created "$B" "$HOME/a" "$HOME/b" "$HOME/c"
  [ -f "$HOME/a" ]; [ ! -e "$HOME/b" ]; [ -f "$HOME/c" ]
  : > "$HOME/c"; chmod 000 "$HOME/c"; fx_drop_blank_created "$B" "$HOME/c"; [ -e "$HOME/c" ]
}
