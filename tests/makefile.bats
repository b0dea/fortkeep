load helpers

setup() { setup_env; unset MAKEFLAGS MFLAGS MAKELEVEL TESTS; }

@test "make with no target prints the sectioned help" {
  run make -C "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dev — set up and run:"* ]]; [[ "$output" == *"Quality — lint / test / scan:"* ]]
  [[ "$output" == *"ci "*"⭐"* ]]; [[ "$output" == *"test-stock"* ]]
  [[ "$output" != *'\033'* ]]
}
@test "recipes stop on a failure inside a pipe, on this Mac's make too" {
  printf 'include %s/Makefile\nprobe:\n\t@false | true\n' "$REPO" > "$BATS_TEST_TMPDIR/probe.mk"
  run make -f "$BATS_TEST_TMPDIR/probe.mk" probe
  [ "$status" -ne 0 ]
}
@test "every standard target exists" {
  for t in help install hooks dev build test test-stock lint format clean ci check; do
    grep -Eq "^$t:" "$REPO/Makefile"
  done
}
@test "make ci runs every step, in order" {
  run make -C "$REPO" -n ci
  [ "$status" -eq 0 ]
  [[ "$output" == *'PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" exec ci/run-tests.sh tests'* ]]
  steps="$(printf '%s\n' "$output" | sed 's/^mise exec -- //')"
  n=0
  for step in '^yamllint ' '^shellcheck -x ' '^ci/check-controls\.sh$' '^ci/run-tests\.sh tests$' \
              'exec ci/run-tests\.sh tests' '^gitleaks git ' '^ci/marker-scan\.sh$'; do
    line="$(printf '%s\n' "$steps" | grep -n -- "$step" | head -1 | cut -d: -f1)"
    [ -n "$line" ]; [ "$line" -gt "$n" ]; n="$line"
  done
  [[ $'\n'"$output" != *$'\n'ci/denylist-scan.sh* ]]  # maintainers only: make scan-private
  run make -C "$REPO" -n check; [ "$status" -eq 0 ]; [[ "$output" == *ci/marker-scan.sh* ]]; [[ $'\n'"$output" != *$'\n'ci/denylist-scan.sh* ]]
}
@test "pre-push runs push-check: ci without the bats tests" {
  grep -Eq '^ +run: make push-check$' "$REPO/lefthook.yml"
  run make -C "$REPO" -n push-check
  [ "$status" -eq 0 ]
  for step in yamllint 'shellcheck -x' ci/check-controls.sh 'gitleaks git' ci/marker-scan.sh; do
    [[ "$output" == *"$step"* ]]
  done
  [[ "$output" != *bats* ]]; [[ $'\n'"$output" != *$'\n'ci/denylist-scan.sh* ]]
}
@test "test-stock keeps the caller's PATH, so a tool found only in a later entry is still found" {
  L="$BATS_TEST_TMPDIR/later"; mkdir -p "$L"
  printf '#!/bin/bash\necho only-in-later-entry\n' > "$L/mise-only-tool"; chmod +x "$L/mise-only-tool"
  run make -C "$REPO" -n test-stock; [ "$status" -eq 0 ]
  recipe="$(printf '%s\n' "$output" | sed 's/^mise exec -- //' | sed 's#exec ci/run-tests.sh tests#exec mise-only-tool#')"
  [[ "$recipe" == *'exec mise-only-tool'* ]]
  PATH="/usr/bin:/bin:$L" run /bin/bash -c "$recipe"
  [ "$status" -eq 0 ]; [ "$output" = "only-in-later-entry" ]
}
@test "make clean removes scratch files and never touches reports/" {
  C="$BATS_TEST_TMPDIR/copy"; mkdir -p "$C/reports/20260101T000000Z" "$C/docs"
  cp "$REPO/Makefile" "$C/"
  : > "$C/reports/20260101T000000Z/results.json"; : > "$C/reports/.DS_Store"; : > "$C/docs/.DS_Store"; : > "$C/.DS_Store"
  run make -C "$C" clean
  [ "$status" -eq 0 ]
  [ -f "$C/reports/20260101T000000Z/results.json" ]; [ -f "$C/reports/.DS_Store" ]
  [ ! -e "$C/docs/.DS_Store" ]; [ ! -e "$C/.DS_Store" ]
}
@test "make hooks unsets only the repo's own core.hooksPath, then installs lefthook's hooks" {
  command -v lefthook >/dev/null || skip "lefthook is not installed"
  T="$BATS_TEST_TMPDIR/repo"; mkdir -p "$T"
  cp "$REPO/Makefile" "$REPO/lefthook.yml" "$T/"
  git -C "$T" init -q -b work
  git -C "$T" config core.hooksPath .githooks
  # MISE= runs the lefthook found above: mise keeps its tools under the real home, which this test replaces.
  run make -C "$T" hooks MISE=
  [ "$status" -eq 0 ]
  run git -C "$T" config --local --get core.hooksPath; [ "$status" -eq 1 ]
  [ -x "$T/.git/hooks/pre-commit" ]; [ -x "$T/.git/hooks/pre-push" ]
}
@test "make hooks warns and skips when the global git config sets core.hooksPath, and leaves it alone" {
  T="$BATS_TEST_TMPDIR/repo"; mkdir -p "$T"
  cp "$REPO/Makefile" "$REPO/lefthook.yml" "$T/"
  git -C "$T" init -q -b work
  git config --global core.hooksPath "$HOME/hooks"
  # Succeeds, so make install still finishes on a Mac with shared global hooks.
  run make -C "$T" hooks
  [ "$status" -eq 0 ]; [[ "$output" == *"WARNING: your global git config sets core.hooksPath"* ]]
  [[ "$output" != *"lefthook install"* ]]; [ ! -e "$T/.git/hooks/pre-commit" ]
  [ "$(git config --global --get core.hooksPath)" = "$HOME/hooks" ]
  [ ! -e "$HOME/hooks/pre-commit" ]
}
@test "the Makefile never writes the global git config" {
  run grep -nE 'git config (set )?--global (--(unset|add|replace)[a-z-]*|[a-z]+\.[A-Za-z]+ )' "$REPO/Makefile"
  [ "$status" -ne 0 ]
}
