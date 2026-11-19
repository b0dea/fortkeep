load helpers

setup() { setup_env; T="$BATS_TEST_TMPDIR/t"; mkdir -p "$T"; }
one() { printf '@test "%s" { %s; }\n' "$2" "$3" >> "$T/$1.bats"; }  # FILE NAME BODY: add one test to FILE.bats

@test "run-tests runs files side by side, prints each whole in name order, and counts what passed" {
  one b "b one" true; one a "a one" true; one a "a two" true
  JOBS=2 run "$REPO/ci/run-tests.sh" "$T"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# $T/a.bats"*"ok 1 a one"*"ok 2 a two"*"# $T/b.bats"*"ok 1 b one"* ]]
  [[ "$output" == *"tests: 3 ok, 0 not ok, in 2 files, 2 at a time"* ]]
}
@test "run-tests fails when a test fails, and when a file can't be run at all" {
  one a "passes" true; one b "fails" false
  JOBS=2 run "$REPO/ci/run-tests.sh" "$T"
  [ "$status" -eq 1 ]; [[ "$output" == *"tests: 1 ok, 1 not ok"* ]]; [[ "$output" == *"failed: $T/b.bats"* ]]
  rm "$T/b.bats"; one b "passes too" true
  printf '@test "never closed" {\n' > "$T/c.bats"  # bats can't run this file, and prints no "not ok" for it
  JOBS=2 run "$REPO/ci/run-tests.sh" "$T"
  [ "$status" -eq 1 ]; [[ "$output" == *"failed: $T/c.bats"* ]]
}
@test "run-tests with one file or JOBS=1 is plain bats, and refuses a JOBS that isn't a number" {
  one a "a one" true; one b "b one" true
  JOBS=4 run "$REPO/ci/run-tests.sh" "$T/a.bats"; [ "$status" -eq 0 ]; [[ "$output" == "1..1"* ]]
  JOBS=1 run "$REPO/ci/run-tests.sh" "$T"; [ "$status" -eq 0 ]; [[ "$output" == "1..2"* ]]
  JOBS=lots run "$REPO/ci/run-tests.sh" "$T"; [ "$status" -eq 1 ]; [[ "$output" == *"JOBS must be a number"* ]]
}
