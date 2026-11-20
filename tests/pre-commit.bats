load helpers

# Hooks are tested only in throwaway repos: a hook test in the real tree can detach it.
setup() {
  setup_env
  T="$BATS_TEST_TMPDIR/repo"; mkdir -p "$T/ci"
  cp "$REPO/ci/pre-commit.sh" "$REPO/ci/no-commit-to-main.sh" "$REPO/ci/denylist-scan.sh" "$REPO/ci/marker-scan.sh" "$T/ci/"
  git -C "$T" init -q -b work
  printf 'acmecorp\n' > "$BATS_TEST_TMPDIR/denylist"; export FORTKEEP_DENYLIST="$BATS_TEST_TMPDIR/denylist"
  printf '%s' 'fortkeep-fake-marker-7Q' | base64 > "$BATS_TEST_TMPDIR/markers.b64"; export FORTKEEP_MARKERS="$BATS_TEST_TMPDIR/markers.b64"
  stub gitleaks 'echo "gitleaks $*" >> "$BATS_TEST_TMPDIR/gitleaks.log"; exit "${GITLEAKS_RC:-0}"'
}
pc() { run bash -c "cd '$T' && ci/pre-commit.sh"; }
stage() { mkdir -p "$T/$(dirname "$1")"; echo "${2:-clean text}" > "$T/$1"; git -C "$T" add -f "$1"; }

@test "pre-commit: clean staged files pass, and gitleaks scans the staged changes" {
  stage a.txt
  pc; [ "$status" -eq 0 ]
  grep -q -- '--pre-commit --staged --redact' "$BATS_TEST_TMPDIR/gitleaks.log"
}
@test "pre-commit: local data and key files are refused by name" {
  local f
  for f in reports/x.json private-paths accepted.json k.pem k.key .env .env.local sub/.env id_ed25519 sub/id_rsa; do
    git -C "$T" reset -q
    stage "$f"
    pc; [ "$status" -eq 1 ]; [[ "$output" == *"$f"* ]]
    git -C "$T" rm -q --cached "$f"
  done
}
@test "pre-commit: look-alike names pass" {
  stage id_ed25519.example; stage docs/env.md; stage keys.md
  pc; [ "$status" -eq 0 ]
}
@test "pre-commit: a gitleaks finding refuses the commit" {
  stage a.txt
  GITLEAKS_RC=1 pc; [ "$status" -eq 1 ]
}
@test "pre-commit: a joined marker refuses the commit, printing only file:line" {
  stage d.js "x = fortkeep-fake-marker-7Q"
  pc; [ "$status" -eq 1 ]; [[ "$output" == *"d.js:1"* ]]
}
@test "pre-commit: a commit goes through when no denylist file exists" {
  export FORTKEEP_DENYLIST="$BATS_TEST_TMPDIR/none"
  stage a.txt
  pc; [ "$status" -eq 0 ]
}
@test "scan-private: a denylisted term fails it, printing only file:line" {
  cp "$REPO/Makefile" "$T/"
  stage b.txt "we work for AcmeCorp"
  run make -C "$T" --no-print-directory scan-private; [ "$status" -ne 0 ]
  [[ "$output" == *"b.txt:1"* ]]; [[ "$output" != *AcmeCorp* ]]
}
@test "scan-private, and so make release, fail when no denylist file exists" {
  export FORTKEEP_DENYLIST="$BATS_TEST_TMPDIR/none"
  cp "$REPO/Makefile" "$T/"; stage a.txt
  run make -C "$T" --no-print-directory scan-private; [ "$status" -ne 0 ]; [[ "$output" == *"no denylist"* ]]
  # -o ci: take ci as done, so only scan-private stands between release and the signing script.
  run make -C "$T" --no-print-directory -o ci release VERSION=v9.9.9; [ "$status" -ne 0 ]; [[ "$output" == *"no denylist"* ]]
  [[ "$output" != *ci/release.sh* ]]
}
@test "no-commit-to-main: refused on main and master, allowed on a branch" {
  run bash -c "cd '$T' && ci/no-commit-to-main.sh"; [ "$status" -eq 0 ]
  git -C "$T" symbolic-ref HEAD refs/heads/main
  run bash -c "cd '$T' && ci/no-commit-to-main.sh"; [ "$status" -eq 1 ]; [[ "$output" == *"on a branch"* ]]
  git -C "$T" symbolic-ref HEAD refs/heads/master
  run bash -c "cd '$T' && ci/no-commit-to-main.sh"; [ "$status" -eq 1 ]
}
@test "lefthook pre-push runs make push-check, also to an empty remote" {
  command -v lefthook >/dev/null || skip "lefthook is not installed"
  stub make 'echo "make $*" >> "$BATS_TEST_TMPDIR/make.log"; env | grep "^GIT_" >> "$BATS_TEST_TMPDIR/make.env"; exit "${MAKE_RC:-0}"'
  cp "$REPO/lefthook.yml" "$T/"
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git -C "$T" remote add origin "$BATS_TEST_TMPDIR/remote.git"
  (cd "$T" && lefthook install -f >/dev/null)
  stage a.txt; git -C "$T" -c user.name=t -c user.email=t@example.com commit -q -m one
  run git -C "$T" push -q origin work; [ "$status" -eq 0 ]
  [ "$(grep -c '^make push-check$' "$BATS_TEST_TMPDIR/make.log")" = 1 ]
  stage b.txt; git -C "$T" -c user.name=t -c user.email=t@example.com commit -q -m two
  MAKE_RC=1 run git -C "$T" push -q origin work; [ "$status" -ne 0 ]
  [ "$(grep -c '^make push-check$' "$BATS_TEST_TMPDIR/make.log")" = 2 ]
  run grep -E '^GIT_(DIR|WORK_TREE|INDEX_FILE|OBJECT_DIRECTORY)=' "$BATS_TEST_TMPDIR/make.env"; [ "$status" -eq 1 ]
}
@test "lefthook wires both: a commit on main is refused, one on a branch goes through" {
  command -v lefthook >/dev/null || skip "lefthook is not installed"
  cp "$REPO/lefthook.yml" "$T/"
  git -C "$T" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first
  (cd "$T" && lefthook install -f >/dev/null)
  stage a.txt
  run git -C "$T" -c user.name=t -c user.email=t@example.com commit -q -m second; [ "$status" -eq 0 ]
  git -C "$T" checkout -q -b main
  stage b.txt
  run git -C "$T" -c user.name=t -c user.email=t@example.com commit -q -m third; [ "$status" -ne 0 ]
  [[ "$output" == *no-commit-to-main* ]]
  git -C "$T" checkout -q work
  stage c.txt "x = fortkeep-fake-marker-7Q"
  run git -C "$T" -c user.name=t -c user.email=t@example.com commit -q -m fourth; [ "$status" -ne 0 ]; [[ "$output" == *"c.txt:1"* ]]
}
