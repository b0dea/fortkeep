load helpers

# A throwaway copy of the repo, in a person's session: the session-start hook warns when its tracked files no longer
# match HEAD. start signs HEAD as a release first (tests/release.bats covers copies that aren't one).
setup() {
  setup_env; person_session
  T="$BATS_TEST_TMPDIR/copy"; mkdir -p "$T"
  git -C "$T" init -q -b main
  signers_into "$T"
  export CLAUDE_PROJECT_DIR="$T"
}
H="$BATS_TEST_DIRNAME/../.claude/hooks"
n=0
start() {
  if [ -z "$(git -C "$T" -c core.fsmonitor= tag --points-at HEAD)" ]; then n=$((n + 1)); sign_release "$T" "v0.0.$n"; fi
  run "$H/session-start.sh" </dev/null; [ "$status" -eq 0 ]; msg="$(jq -r .systemMessage <<<"$output")"
}

@test "a copy's own core.fsmonitor is not run by the hook" {
  echo x > "$T/f"; commit "$T"
  printf '#!/bin/bash\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" > "$T/mon"; chmod +x "$T/mon"
  git -C "$T" config core.fsmonitor "$T/mon"
  start
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}
@test "a copy's own clean filter is not run by the hook, and the local filter setting counts as a local change" {
  echo hi > "$T/f.txt"; echo '*.txt filter=x' > "$T/.gitattributes"; commit "$T"
  git -C "$T" config filter.x.clean "touch $BATS_TEST_TMPDIR/ran; cat"
  touch -t 203001010000 "$T/f.txt"
  start
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]; [[ "$msg" == *"local changes"* ]]
}
@test "a change hidden with skip-worktree or assume-unchanged still counts as a local change" {
  echo hi > "$T/f.sh"; echo hi > "$T/g.sh"; commit "$T"
  echo evil > "$T/f.sh"; git -C "$T" update-index --skip-worktree f.sh
  start
  [[ "$msg" == *"WARNING"*"local changes"*"Don't run fixes; reinstall a signed release unless you made these changes yourself."* ]]
  git -C "$T" update-index --no-skip-worktree f.sh; git -C "$T" checkout -q f.sh
  echo evil > "$T/g.sh"; git -C "$T" update-index --assume-unchanged g.sh
  start
  [[ "$msg" == *"local changes"* ]]
}
@test "local changes: content, executable bit, a missing file and a symlink's target each count" {
  echo hi > "$T/f"; printf '#!/bin/sh\n' > "$T/x.sh"; chmod +x "$T/x.sh"; ln -s f "$T/l"; commit "$T"
  start; [[ "$msg" != *"local changes"* ]]
  chmod -x "$T/x.sh"; start; [[ "$msg" == *"local changes"* ]]; chmod +x "$T/x.sh"
  chmod +x "$T/f"; start; [[ "$msg" == *"local changes"* ]]; chmod -x "$T/f"
  rm "$T/f"; start; [[ "$msg" == *"local changes"* ]]; echo hi > "$T/f"
  ln -sf x.sh "$T/l"; start; [[ "$msg" == *"local changes"* ]]; ln -sf f "$T/l"
  start; [[ "$msg" != *"local changes"* ]]
}
@test "a replace ref can't stand an earlier commit in for a changed HEAD" {
  echo hi > "$T/f.sh"; commit "$T"; local good; good="$(git -C "$T" rev-parse HEAD)"
  echo evil > "$T/f.sh"; commit "$T"
  git -C "$T" replace "$(git -C "$T" rev-parse HEAD)" "$good"
  start; [[ "$msg" != *"local changes"* ]]
  echo evil2 > "$T/f.sh"; start; [[ "$msg" == *"local changes"* ]]
}
@test "an untracked file where agents load config counts as a local change; others don't" {
  echo hi > "$T/f"; commit "$T"
  echo x > "$T/notes.txt"; start; [[ "$msg" != *"local changes"* ]]
  for f in .opencode/plugins/x.ts .claude/settings.local.json .codex/hooks.json .agents/skills/x/SKILL.md opencode.json; do
    mkdir -p "$T/$(dirname "$f")"; echo x > "$T/$f"
    start; [[ "$msg" == *"local changes"* ]]
    rm "$T/$f"
  done
}
