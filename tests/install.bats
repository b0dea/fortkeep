load helpers
bats_require_minimum_version 1.5.0

# install.sh: a first install trusts one pinned release commit and nothing else, since nothing on this Mac yet says
# which signers to trust. $O is a throwaway "GitHub" holding release v0.1.0, signed with the test key its own signers
# list names.
setup_file() {
  signed_origin bin checks
}
setup() {
  setup_env
  copy_signed_origin
  C="$(git -C "$O" rev-parse HEAD)"
  export FORTKEEP_INSTALL_URL="$O"
  stub sw_vers 'echo 15.7.9'
  stub xcode-select '[ "$1" = -p ] && echo /Library/Developer/CommandLineTools'
  DEST="$HOME/.local/share/fortkeep"
}
install() { run "$REPO/install.sh" "$@"; }
installed_release() {  # the copy it made is release v0.1.0, unchanged, to fortkeep itself
  run "$DEST/bin/fortkeep" version --json
  [ "$(field version)" = v0.1.0 ]; [ "$(field local_changes)" = false ]
}
nothing_installed() { [ ! -e "$DEST" ]; [ ! -e "$HOME/.config/fortkeep/release-signers" ]; [ -z "$(ls -A "$HOME/.local/share" 2>/dev/null)" ]; }

@test "installs the pinned release, records its signers as trusted, links the command and says what's next" {
  mkdir -p "$HOME/.local/bin"
  install --tag v0.1.0 --commit "$C"
  [ "$status" -eq 0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$C" ]
  [ "$(cat "$HOME/.config/fortkeep/highest-release")" = v0.1.0 ]
  cmp "$HOME/.config/fortkeep/release-signers" "$O/.github/allowed_signers"
  [ "$(readlink "$HOME/.local/bin/fortkeep")" = "$DEST/bin/fortkeep" ]
  [[ "$output" == *"fortkeep agent"* ]]
  [[ "$output" != *"warning:"* ]]  # git 2.54's clone --branch of a signed tag warned "is not a commit!"
  installed_release
}

@test "without ~/.local/bin, or with --no-link, it links nothing and says how to run it" {
  install --tag v0.1.0 --commit "$C"
  [ "$status" -eq 0 ]; [ ! -e "$HOME/.local/bin/fortkeep" ]
  [[ "$output" == *'export PATH="$HOME/.local/share/fortkeep/bin:$PATH"'* ]]
  rm -rf "$DEST"; mkdir -p "$HOME/.local/bin"
  install --tag v0.1.0 --commit "$C" --no-link
  [ "$status" -eq 0 ]; [ ! -e "$HOME/.local/bin/fortkeep" ]; [[ "$output" != *"export PATH"* ]]
}

@test "refuses a release whose commit isn't the pinned one, and leaves nothing behind" {
  install --tag v0.1.0 --commit 0123456789abcdef0123456789abcdef01234567
  [ "$status" -eq 1 ]; [[ "$output" == *"not the pinned"* ]]
  nothing_installed
}

@test "refuses a tag that isn't signed by a key the pinned commit's signers list names" {
  echo next > "$O/next"; commit "$O"; C2="$(git -C "$O" rev-parse HEAD)"
  git -C "$O" -c user.name=t -c user.email=t@example.com tag -a -m "b0dea/fortkeep v0.2.0" v0.2.0
  install --tag v0.2.0 --commit "$C2"
  [ "$status" -eq 1 ]; [[ "$output" == *"not signed"* ]]
  nothing_installed
  ssh-keygen -q -t ed25519 -N '' -C other -f "$BATS_TEST_TMPDIR/other"
  git -C "$O" -c user.name=t -c user.email=t@example.com -c gpg.format=ssh -c user.signingkey="$BATS_TEST_TMPDIR/other" \
    tag -s -m "b0dea/fortkeep v0.3.0" v0.3.0
  install --tag v0.3.0 --commit "$C2"
  [ "$status" -eq 1 ]; [[ "$output" == *"not signed"* ]]
  nothing_installed
}

@test "refuses a tag that is not the commit its same-named branch is" {
  echo next > "$O/next"; commit "$O"; sign_release "$O" v0.2.0
  git -C "$O" branch v0.2.0 "$C"  # a branch of the tag's name, at the pinned commit; the tag is elsewhere
  install --tag v0.2.0 --commit "$C"
  [ "$status" -eq 1 ]; [[ "$output" == *"not the pinned"* ]]
  nothing_installed
}

@test "runs nothing from a clone before its commit is verified" {
  printf 'touch "$HOME/clone-code-ran"\n' >> "$O/checks/lib/repo.sh"; commit "$O"; sign_release "$O" v0.2.0
  install --tag v0.2.0 --commit "$C"
  [ "$status" -eq 1 ]; [ ! -e "$HOME/clone-code-ran" ]
  nothing_installed
}

@test "git hook templates from the person's git config don't end up in the copy" {
  mkdir -p "$HOME/tpl/hooks"; printf '#!/bin/sh\n' > "$HOME/tpl/hooks/pre-commit"; chmod +x "$HOME/tpl/hooks/pre-commit"
  git config --file "$HOME/.gitconfig" init.templateDir "$HOME/tpl"
  install --tag v0.1.0 --commit "$C"
  [ "$status" -eq 0 ]
  installed_release
}

@test "a hook folder in the person's own git config doesn't make the copy look changed" {
  mkdir -p "$HOME/hooks"; printf '#!/bin/sh\n' > "$HOME/hooks/pre-commit"
  git config --file "$HOME/.gitconfig" core.hooksPath "$HOME/hooks"
  install --tag v0.1.0 --commit "$C"
  [ "$status" -eq 0 ]
  installed_release
}

@test "refuses a Mac older than macOS 15" {
  stub sw_vers 'echo 14.7.1'
  install --tag v0.1.0 --commit "$C"
  [ "$status" -eq 1 ]; [[ "$output" == *"macOS 15"* ]]
  nothing_installed
}

@test "without Apple's Command Line Tools it says how to install them" {
  stub xcode-select 'exit 2'
  install --tag v0.1.0 --commit "$C"
  [ "$status" -eq 1 ]; [[ "$output" == *"xcode-select --install"* ]]
  nothing_installed
}

@test "refuses to run with no release pinned, or with a malformed pin" {
  # A released install.sh carries its pins, so blank them in a copy to see the refusal.
  sed -e 's/^PIN_TAG=.*/PIN_TAG=""/' -e 's/^PIN_COMMIT=.*/PIN_COMMIT=""/' "$REPO/install.sh" > "$BATS_TEST_TMPDIR/unpinned.sh"
  run bash "$BATS_TEST_TMPDIR/unpinned.sh"
  [ "$status" -eq 1 ]; [[ "$output" == *"no release is pinned"* ]]
  install --tag main --commit "$C"
  [ "$status" -eq 1 ]
  install --tag v0.1.0 --commit 'HEAD'
  [ "$status" -eq 1 ]
  install --bogus
  [ "$status" -eq 2 ]
  nothing_installed
}

@test "never replaces an existing install" {
  mkdir -p "$DEST"; echo mine > "$DEST/file"
  install --tag v0.1.0 --commit "$C"
  [ "$status" -eq 1 ]; [[ "$output" == *"fortkeep update"* ]]
  [ "$(cat "$DEST/file")" = mine ]
}

@test "the Homebrew shim installs on first run without mixing the installer's output into fortkeep's JSON" {
  # The shim as the formula writes it, with this release's pins and this repo's install.sh as its libexec copy
  awk '/<<~SH$/ { on = 1; next } /^ *SH$/ { on = 0 } on' "$REPO/packaging/homebrew/fortkeep.rb" \
    | sed -e 's/^      //' -e "s|#{libexec}|$REPO|" -e 's|#{version}|0.1.0|' -e "s|#{COMMIT}|$C|" > "$BATS_TEST_TMPDIR/shim"
  grep -q "install.sh\" --tag \"v0.1.0\" --commit \"$C\"" "$BATS_TEST_TMPDIR/shim"
  run --separate-stderr bash "$BATS_TEST_TMPDIR/shim" version --json
  [ "$status" -eq 0 ]
  [ "$(field version)" = v0.1.0 ]
  [[ "$stderr" == *"Installed fortkeep v0.1.0"* ]]
}

@test "a second install that finishes while this one clones wins, and this one never nests its clone inside it" {
  # git that, on fetch, first lets another install finish: DEST appears, holding a copy
  real="$(command -v git)"
  stub git "case \" \$* \" in *\" fetch \"*) mkdir -p \"$DEST/bin\"; echo theirs > \"$DEST/bin/fortkeep\" ;; esac; exec \"$real\" \"\$@\""
  install --tag v0.1.0 --commit "$C"
  [ "$status" -eq 1 ]; [[ "$output" == *"another install got there first"* ]]
  [ ! -e "$DEST/fortkeep" ]; [ "$(cat "$DEST/bin/fortkeep")" = theirs ]
  [ ! -e "$HOME/.config/fortkeep/release-signers" ]
}
