load helpers
. "$BATS_TEST_DIRNAME/../checks/lib/repo.sh"

# A throwaway "GitHub" ($O) and a clone of it ($T). Keys a and b live in $BATS_TEST_TMPDIR; the clone starts on
# main at v1.0.0 and lists only key a as a release signer.
setup() {
  setup_env
  K="$BATS_TEST_TMPDIR/keys"; mkdir -p "$K"
  ssh-keygen -q -t ed25519 -N '' -C a -f "$K/a"; ssh-keygen -q -t ed25519 -N '' -C b -f "$K/b"
  O="$BATS_TEST_TMPDIR/origin"; mkdir -p "$O/.github"; git -C "$O" init -q -b main
  signers a; release v1.0.0 a
  T="$BATS_TEST_TMPDIR/copy"; git clone -q "$O" "$T"
}
signer_line() { printf '%s namespaces="git" %s\n' "$1" "$(cut -d' ' -f1,2 "$K/$1.pub")"; }
signers() {  # KEY... — origin's signers list names exactly these keys
  local k; for k in "$@"; do signer_line "$k"; done > "$O/.github/allowed_signers"
}
tag_as() {  # KEY ARGS... — git tag in origin, signing (when ARGS ask for it) with KEY
  local k="$1"; shift
  git -C "$O" -c user.name=t -c user.email="$k@example.com" -c gpg.format=ssh -c user.signingkey="$K/$k" tag "$@"
}
release() {  # TAG KEY — a new commit on origin, tagged TAG as a release and signed with KEY
  echo "$1" > "$O/version"; commit "$O"; tag_as "$2" -s -m "$DEVWARD_RELEASE_NAME $1" "$1"
}
# update.sh allows only https and ssh remotes; this throwaway "GitHub" is a local folder, so the tests run a copy that
# also allows git's file transport. The last tests run the real script.
update() {
  U="$BATS_TEST_TMPDIR/u"
  if [ ! -d "$U" ]; then
    mkdir -p "$U"; cp -R "$REPO/checks" "$U/"
    sed -i '' 's/-c protocol.allow=never/& -c protocol.file.allow=always/' "$U/checks/update.sh"
    grep -q 'protocol.file.allow=always' "$U/checks/update.sh"
  fi
  DEVWARD_REPO="$T" run "$U/checks/update.sh"
}
on() { [ "$(git -C "$T" rev-parse HEAD)" = "$(git -C "$O" rev-parse "$1^{commit}")" ]; }  # TAG — the clone is on it
detached() { ! git -C "$T" symbolic-ref -q HEAD; }

@test "update.sh moves the copy to the newest release a listed maintainer signed, and off its branch" {
  update; [ "$status" -eq 0 ]; on v1.0.0; detached   # nothing newer yet: it still leaves main for the release
  release v1.9.0 a; release v1.10.0 a
  update; [ "$status" -eq 0 ]; [[ "$output" == *"v1.10.0"* ]]; on v1.10.0; detached
  update; [ "$status" -eq 0 ]; [[ "$output" == *"Already on the newest release"* ]]; on v1.10.0
}
@test "update.sh passes over a newer tag that isn't a release a listed maintainer signed, and names it" {
  release v1.1.0 a
  echo evil > "$O/version"; commit "$O"
  tag_as a v2.0.0                                                        # no tag object at all
  tag_as a -a -m "$DEVWARD_RELEASE_NAME v2.1.0" v2.1.0                         # a tag object without a signature
  git -C "$O" update-ref refs/tags/v2.2.0 "$(git -C "$O" rev-parse refs/tags/v1.0.0)"  # an old release, renamed
  tag_as a -s -m "another/repo v2.3.0" v2.3.0                            # signed by a maintainer, for another repo
  signers a b; commit "$O"
  tag_as b -s -m "$DEVWARD_RELEASE_NAME v2.4.0" v2.4.0                         # signed by a key only its own tree lists
  update; [ "$status" -eq 0 ]; on v1.1.0
  for t in v2.0.0 v2.1.0 v2.2.0 v2.3.0 v2.4.0; do [[ "$output" == *"$t"* ]]; done
}
@test "update.sh still updates when a tag the copy already has was moved on GitHub" {
  release v1.1.0 a
  echo evil > "$O/version"; commit "$O"; tag_as a -f v1.0.0
  update; [ "$status" -eq 0 ]; on v1.1.0
}
@test "update.sh refuses a copy with local changes, so an edited signers list can't vouch for a release" {
  release v1.1.0 b
  signer_line b >> "$T/.github/allowed_signers"
  update; [ "$status" -eq 1 ]; [[ "$output" == *"local changes"* ]]; on v1.0.0
}
@test "update.sh follows a release that hands signing to a new key" {
  signers a b; release v1.1.0 a
  signers b; release v1.2.0 b
  update; [ "$status" -eq 0 ]; on v1.2.0
}
@test "update.sh only moves a copy forward once it follows releases" {
  signers b; release v1.1.0 a                    # from v1.1.0 on, only b signs
  update; [ "$status" -eq 0 ]; on v1.1.0
  git -C "$O" checkout -q v1.0.0
  echo old > "$O/version"; commit "$O"; tag_as b -s -m "$DEVWARD_RELEASE_NAME v1.5.0" v1.5.0   # newer name, older line
  update; [ "$status" -eq 0 ]; on v1.1.0
}
@test "update.sh records the highest release this Mac has run (A11)" {
  release v1.1.0 a
  update; [ "$status" -eq 0 ]; [ "$(cat "$HOME/.config/devward/highest-release")" = v1.1.0 ]
}
@test "update.sh refuses a copy with an ignored plugin, a git hook or a local setting that runs a command (A5, A11)" {
  release v1.1.0 a
  mkdir -p "$T/.opencode/plugin"; echo x > "$T/.opencode/plugin/evil.ts"; echo .opencode/ >> "$T/.git/info/exclude"  # ignored
  update; [ "$status" -eq 1 ]; [[ "$output" == *".opencode/plugin/evil.ts"* ]]; on v1.0.0; rm -r "$T/.opencode"
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" > "$T/.git/hooks/post-checkout"; chmod +x "$T/.git/hooks/post-checkout"
  update; [ "$status" -eq 1 ]; [[ "$output" == *"git hook post-checkout"* ]]; rm "$T/.git/hooks/post-checkout"
  for kv in core.hooksPath=/tmp/h filter.x.smudge=cat core.sshCommand=/tmp/x remote.origin.uploadpack=/tmp/x; do
    git -C "$T" config "${kv%%=*}" "${kv#*=}"
    update; [ "$status" -eq 1 ]; [[ "$output" == *"git setting"* ]]; on v1.0.0
    git -C "$T" config --unset "${kv%%=*}"
  done
  echo '* filter=x' > "$T/.git/info/attributes"; update; [ "$status" -eq 1 ]; [[ "$output" == *"info/attributes"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}
@test "update.sh records where it fetched from at the first verified install, then refuses any other origin (A18)" {
  release v1.1.0 a
  update; [ "$status" -eq 0 ]; on v1.1.0; [ "$(cat "$HOME/.config/devward/origin")" = "$O" ]
  release v1.2.0 a
  M="$BATS_TEST_TMPDIR/mirror"; git clone -q --mirror "$O" "$M"
  git -C "$T" remote set-url origin "$M"
  update; [ "$status" -eq 1 ]; [[ "$output" == *"~/.config/devward/origin"* ]]; [[ "$output" != *"$M"* ]]; on v1.1.0
  git -C "$T" remote set-url origin "$O"; git -C "$T" config --add remote.origin.url "$M"   # a second place to fetch from
  update; [ "$status" -eq 1 ]; on v1.1.0
  git -C "$T" config --unset-all remote.origin.url; git -C "$T" config remote.origin.url "$O"
  update; [ "$status" -eq 0 ]; on v1.2.0
}
@test "A23: update.sh refuses a url insteadOf or pushInsteadOf setting, global or local, that rewrites origin, and prints no URL" {
  release v1.1.0 a
  M="$BATS_TEST_TMPDIR/mirror"; git clone -q --mirror "$O" "$M"
  refused() { update; [ "$status" -eq 1 ]; [[ "$output" != *"$M"* ]]; [[ "$output" != *"$O"* ]]; on v1.0.0; }
  git config --global "url.$M.insteadOf" "$O"; refused; [[ "$output" == *insteadOf* ]]
  git config --global --unset "url.$M.insteadOf"
  git config --global "url.$M.pushInsteadOf" "${O%/*}"; refused     # a prefix of the address is enough
  git config --global --unset "url.$M.pushInsteadOf"
  git -C "$T" config "url.$M.insteadOf" "$O"; refused
  git -C "$T" config --unset "url.$M.insteadOf"
  git config --global "url.$M.insteadOf" "https://example.com/"     # rewrites some other address only
  update; [ "$status" -eq 0 ]; on v1.1.0
}
@test "A23: outside the suite, what update.sh records lives under the account's own home, whatever HOME says" {
  acct="$(/usr/bin/perl -e 'print +(getpwuid($<))[7]')"
  run env -u BATS_TEST_TMPDIR HOME="$BATS_TEST_TMPDIR/elsewhere" /bin/bash -c \
    '. "$1"; devward_origin_file; devward_highest_file; devward_trusted_signers_file' _ "$REPO/checks/lib/repo.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$acct/.config/devward/origin"$'\n'"$acct/.config/devward/highest-release"$'\n'"$acct/.config/devward/release-signers" ]
}
@test "the real update.sh fetches over https or ssh only: an ext:: or local remote runs nothing (A11)" {
  release v1.1.0 a
  git -C "$T" remote set-url origin "ext::sh -c touch% $BATS_TEST_TMPDIR/ran"
  DEVWARD_REPO="$T" run "$REPO/checks/update.sh"; [ "$status" -eq 1 ]; [ ! -e "$BATS_TEST_TMPDIR/ran" ]; on v1.0.0
  git -C "$T" remote set-url origin "$O"
  DEVWARD_REPO="$T" run "$REPO/checks/update.sh"; [ "$status" -eq 1 ]; on v1.0.0
}

# make release's tagging step, in a throwaway repo whose own config holds the maintainer's signing key.
@test "release.sh keeps a tag only when copies on the last release and fresh clones would both accept it" {
  git -C "$O" config gpg.format ssh; git -C "$O" config user.name t; git -C "$O" config user.email t@example.com
  tag_it() { DEVWARD_REPO="$O" run "$REPO/ci/release.sh" v1.1.0; }
  refused() { [ "$status" -eq 1 ]; ! git -C "$O" rev-parse -q --verify refs/tags/v1.1.0; }
  signers a b; echo next > "$O/version"; commit "$O"
  git -C "$O" config user.signingkey "$K/b"; tag_it; refused   # b is listed on main, but not in v1.0.0
  signers b; commit "$O"
  git -C "$O" config user.signingkey "$K/a"; tag_it; refused   # a is listed in v1.0.0, but no longer on main
  signers a b; commit "$O"
  tag_it; [ "$status" -eq 0 ]
  update; [ "$status" -eq 0 ]; [[ "$output" == *"Updated to v1.1.0"* ]]; on v1.1.0
}
@test "release.sh, run in development mode, still refuses local changes and files or git settings that change what runs (A18)" {
  git -C "$O" config gpg.format ssh; git -C "$O" config user.name t; git -C "$O" config user.email t@example.com
  git -C "$O" config user.signingkey "$K/a"
  tag_it() { DEVWARD_REPO="$O" run "$REPO/ci/release.sh" v1.1.0; }
  refused() { [ "$status" -eq 1 ]; ! git -C "$O" rev-parse -q --verify refs/tags/v1.1.0; }
  echo next > "$O/version"; commit "$O"
  devward_dev_session   # a maintainer's Mac: DEVWARD_DEV=1 and the marker
  echo x >> "$O/version"; tag_it; refused; git -C "$O" checkout -q version
  mkdir -p "$O/.opencode/plugin"; echo x > "$O/.opencode/plugin/evil.ts"; echo .opencode/ >> "$O/.git/info/exclude"
  tag_it; refused; [[ "$output" == *".opencode/plugin/evil.ts"* ]]; rm -r "$O/.opencode"
  git -C "$O" config core.hooksPath "$BATS_TEST_TMPDIR/h"; tag_it; refused; git -C "$O" config --unset core.hooksPath
  # the git hooks make install puts on a maintainer's Mac: none runs while a tag is made
  printf '#!/bin/sh\n' > "$O/.git/hooks/pre-push"; chmod +x "$O/.git/hooks/pre-push"
  tag_it; [ "$status" -eq 0 ]
}
@test "A24: release.sh runs no git hook while it tags, not even one that runs on every ref change" {
  git -C "$O" config gpg.format ssh; git -C "$O" config user.name t; git -C "$O" config user.email t@example.com
  echo next > "$O/version"; commit "$O"
  H="$O/.git/hooks/reference-transaction"
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" > "$H"; chmod +x "$H"
  git -C "$O" config user.signingkey "$K/b"   # not a listed signer: the tag is made, then removed
  DEVWARD_REPO="$O" run "$REPO/ci/release.sh" v1.1.0; [ "$status" -eq 1 ]; ! git -C "$O" rev-parse -q --verify refs/tags/v1.1.0
  git -C "$O" config user.signingkey "$K/a"
  DEVWARD_REPO="$O" run "$REPO/ci/release.sh" v1.1.0; [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}
