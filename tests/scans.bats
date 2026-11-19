load helpers

setup() {
  T="$BATS_TEST_TMPDIR/repo"; mkdir -p "$T/ci"
  cp "$REPO/ci/denylist-scan.sh" "$REPO/ci/marker-scan.sh" "$T/ci/"
  git -C "$T" init -q -b main
  echo "clean text" > "$T/a.txt"
  git -C "$T" add -A
  printf 'acmecorp\n' > "$BATS_TEST_TMPDIR/denylist"
  export DEVWARD_DENYLIST="$BATS_TEST_TMPDIR/denylist"
  # Harmless fake marker: real markers are never written to disk by tests.
  printf '%s' 'devward-fake-marker-7Q' | base64 > "$BATS_TEST_TMPDIR/markers.b64"
  export DEVWARD_MARKERS="$BATS_TEST_TMPDIR/markers.b64"
}

@test "denylist: clean tree passes" {
  run "$T/ci/denylist-scan.sh"; [ "$status" -eq 0 ]
}
@test "denylist: a hit fails and prints only file:line" {
  echo "we work for AcmeCorp" > "$T/b.txt"; git -C "$T" add b.txt
  run "$T/ci/denylist-scan.sh"; [ "$status" -eq 1 ]
  [[ "$output" == *"b.txt:1"* ]]; [[ "$output" != *AcmeCorp* ]]
}
@test "denylist: --staged sees staged content, not the worktree" {
  echo "acmecorp" > "$T/c.txt"; git -C "$T" add c.txt
  echo "clean again" > "$T/c.txt"
  run "$T/ci/denylist-scan.sh" --staged; [ "$status" -eq 1 ]
  [[ "$output" == *"c.txt:1"* ]]
  run "$T/ci/denylist-scan.sh"; [ "$status" -eq 0 ]
}
@test "denylist: empty list fails" {
  : > "$BATS_TEST_TMPDIR/denylist"
  run "$T/ci/denylist-scan.sh"; [ "$status" -eq 1 ]
}
@test "denylist: blank or comment-only list fails" {
  printf '\n' > "$BATS_TEST_TMPDIR/denylist"
  run "$T/ci/denylist-scan.sh"; [ "$status" -eq 1 ]
  printf '# note\n\n  \n' > "$BATS_TEST_TMPDIR/denylist"
  run "$T/ci/denylist-scan.sh"; [ "$status" -eq 1 ]
}
@test "denylist: a git grep error is not reported clean" {
  echo garbage > "$T/.git/index"
  run "$T/ci/denylist-scan.sh"; [ "$status" -ne 0 ]
  [[ "$output" != *clean* ]]
}
@test "denylist: missing list fails" {
  export DEVWARD_DENYLIST="$BATS_TEST_TMPDIR/none"
  run "$T/ci/denylist-scan.sh"; [ "$status" -eq 1 ]
}
@test "markers: clean tree passes" {
  run "$T/ci/marker-scan.sh"; [ "$status" -eq 0 ]
}
@test "markers: a joined marker fails, fragments don't" {
  echo "x = devward-fake-marker-7Q" > "$T/d.js"
  echo "'devward-fake-' + 'marker-7Q'" > "$T/e.py"
  git -C "$T" add d.js e.py
  run "$T/ci/marker-scan.sh"; [ "$status" -eq 1 ]
  [[ "$output" == *"d.js:1"* ]]; [[ "$output" != *"e.py"* ]]
  [[ "$output" != *"devward-fake-marker-7Q"* ]]
}
@test "markers: fragments only passes" {
  echo "'devward-fake-' + 'marker-7Q'" > "$T/e.py"; git -C "$T" add e.py
  run "$T/ci/marker-scan.sh"; [ "$status" -eq 0 ]
}
@test "markers: missing markers file fails" {
  export DEVWARD_MARKERS="$BATS_TEST_TMPDIR/none"
  run "$T/ci/marker-scan.sh"; [ "$status" -eq 1 ]
}
@test "markers: --staged sees staged content, not the worktree" {
  echo "x = devward-fake-marker-7Q" > "$T/d.js"; git -C "$T" add d.js
  echo "clean again" > "$T/d.js"
  run "$T/ci/marker-scan.sh" --staged; [ "$status" -eq 1 ]
  [[ "$output" == *"d.js:1"* ]]
  run "$T/ci/marker-scan.sh"; [ "$status" -eq 0 ]
}
@test "markers: a markers file with no markers fails" {
  printf '\n' > "$DEVWARD_MARKERS"
  run "$T/ci/marker-scan.sh"; [ "$status" -eq 1 ]
}
@test "markers: a git grep error is not reported clean" {
  echo garbage > "$T/.git/index"
  run "$T/ci/marker-scan.sh"; [ "$status" -ne 0 ]
  [[ "$output" != *clean* ]]
}
