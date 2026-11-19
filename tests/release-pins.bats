load helpers

# ci/release-pins.sh: the values a published release pins in install.sh, the Homebrew formula and the README. Run from
# a throwaway release ($O); curl is a stub that serves fixed bytes as GitHub's tarball.
setup_file() {
  signed_origin ci checks install.sh
}
setup() {
  setup_env
  copy_signed_origin
  C="$(git -C "$O" rev-parse HEAD)"
  export DEVWARD_REPO="$O"
  stub curl 'while [ $# -gt 0 ]; do case "$1" in -o) o="$2"; shift 2 ;; https://*) echo "$1" > "$BATS_TEST_TMPDIR/url"; shift ;; *) shift ;; esac; done
printf "tarball-bytes" > "$o"'
  TARSHA="$(printf 'tarball-bytes' | shasum -a 256 | cut -d' ' -f1)"
}
pins() { run "$O/ci/release-pins.sh" "$@"; }

@test "prints the tag's commit, the tarball's SHA-256, and the lines to paste into install.sh, the formula and the README" {
  pins v0.1.0
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/url")" = https://github.com/b0dea/devward/archive/refs/tags/v0.1.0.tar.gz ]
  [[ "$output" == *"PIN_TAG=\"v0.1.0\""* ]]; [[ "$output" == *"PIN_COMMIT=\"$C\""* ]]
  [[ "$output" == *"url \"https://github.com/b0dea/devward/archive/refs/tags/v0.1.0.tar.gz\""* ]]
  [[ "$output" == *"sha256 \"$TARSHA\""* ]]; [[ "$output" == *"COMMIT = \"$C\""* ]]
  # The installer's SHA-256 is the one install.sh has once those two lines are pasted in
  sed -e "s/^PIN_TAG=.*/PIN_TAG=\"v0.1.0\"/" -e "s/^PIN_COMMIT=.*/PIN_COMMIT=\"$C\"/" "$REPO/install.sh" > "$BATS_TEST_TMPDIR/pinned.sh"
  [[ "$output" == *"$(shasum -a 256 < "$BATS_TEST_TMPDIR/pinned.sh" | cut -d' ' -f1)"* ]]
  ! cmp -s "$BATS_TEST_TMPDIR/pinned.sh" "$REPO/install.sh"
}

@test "refuses a tag that isn't a signed release" {
  echo next > "$O/next"; commit "$O"
  git -C "$O" -c user.name=t -c user.email=t@example.com tag -a -m "b0dea/devward v0.2.0" v0.2.0
  pins v0.2.0
  [ "$status" -eq 1 ]; [[ "$output" == *"not signed"* ]]
  pins v9.9.9
  [ "$status" -eq 1 ]
}

@test "refuses a malformed version, and a tarball it couldn't download" {
  pins 0.1.0; [ "$status" -eq 2 ]
  pins; [ "$status" -eq 2 ]
  stub curl 'exit 22'
  pins v0.1.0
  [ "$status" -eq 1 ]; [[ "$output" == *"could not download"* ]]
}

@test "refuses an install.sh with a pin line twice" {
  printf 'PIN_TAG=""\n' >> "$O/install.sh"
  pins v0.1.0
  [ "$status" -eq 1 ]; [[ "$output" == *"exactly one PIN_TAG= line"* ]]
}
