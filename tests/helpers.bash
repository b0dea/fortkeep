REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup_env() {
  unset ZDOTDIR BASH_ENV CLAUDE_CONFIG_DIR CLAUDECODE CODEX_HOME XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM
  for v in $(env | sed -n 's/^\(SAFE_CHAIN_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done
  export DEVWARD_REPO="$REPO"
  export DEVWARD_REPORTS="$BATS_TEST_TMPDIR/reports"
  export DEVWARD_PRIVATE_PATHS="$BATS_TEST_TMPDIR/private-paths"
  export DEVWARD_ACCEPTED="$BATS_TEST_TMPDIR/accepted.json"
  export DEVWARD_CONFIG="$DEVWARD_REPORTS/config.json"
  export DEVWARD_SYSROOT="$BATS_TEST_TMPDIR/root"
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEVWARD_BACKUPS="$HOME/.local/state/devward/backups"   # the real default, under the test HOME
  # The tests run on an untagged tree, like a development session: the guards use the development deny-list and the
  # release checks let it through. That takes DEVWARD_DEV=1 and the person's marker, here in the test's own HOME; the
  # real HOME's marker never counts under the suite (checks/lib/mode.sh). A test of a person's session unsets the
  # variable (person_session).
  export DEVWARD_DEV=1
  mkdir -p "$DEVWARD_REPORTS" "$DEVWARD_SYSROOT" "$HOME" "$BATS_TEST_TMPDIR/bin"
  dev_marker
  # Checks honour the DEVWARD_* settings above and the stubs in bin/ only under the test suite: this marker, with HOME
  # inside the same folder (checks/lib/common.sh, devward_under_test).
  : > "$BATS_TEST_TMPDIR/.devward-test"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

dev_marker() { mkdir -p "$HOME/.config/devward" && : > "$HOME/.config/devward/dev"; }  # the person's development marker, in this HOME
person_session() { unset DEVWARD_DEV; }  # what a person's agent runs under: the allow-list and the release checks

# Releases in throwaway repos, signed with a test key that lives in $BATS_TEST_TMPDIR/keys.
release_key() {
  K="$BATS_TEST_TMPDIR/keys"
  [ -f "$K/rel" ] || { mkdir -p "$K"; ssh-keygen -q -t ed25519 -N '' -C rel -f "$K/rel"; }
}
signers_into() {  # REPO — its .github/allowed_signers lists only the test release key
  release_key; mkdir -p "$1/.github"
  printf 'rel namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$K/rel.pub")" > "$1/.github/allowed_signers"
}
sign_release() {  # REPO TAG — HEAD becomes release TAG, signed with the test release key
  release_key
  git -C "$1" -c core.fsmonitor= -c user.name=t -c user.email=t@example.com -c gpg.format=ssh -c user.signingkey="$K/rel" \
    tag -s -m "b0dea/devward $2" "$2"
}
release_tree() {  # DIR PATH... — DIR becomes a git checkout of release v0.1.0 holding these paths from this repo
  local d="$1" p; shift
  mkdir -p "$d"; git -C "$d" init -q -b main
  for p in "$@"; do mkdir -p "$d/$(dirname "$p")"; cp -R "$REPO/$p" "$d/$p"; done
  signers_into "$d"; commit "$d"; sign_release "$d" v0.1.0
}

stub() {  # stub NAME 'bash body' — fake command placed first on PATH
  printf '#!/bin/bash\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

fix_tree() {  # a copy of checks/ and fixes/ whose fix.sh also finds this test's stub commands
  T="$BATS_TEST_TMPDIR/tree"; mkdir -p "$T"
  cp -R "$REPO/checks" "$REPO/fixes" "$T/"
  sed -i '' "s#^PATH=/usr/bin:#PATH=$BATS_TEST_TMPDIR/bin:/usr/bin:#" "$T/fixes/lib/fix.sh"
  grep -q "^PATH=$BATS_TEST_TMPDIR/bin:" "$T/fixes/lib/fix.sh"
  export DEVWARD_REPORTS="$T/reports"
  mkdir -p "$DEVWARD_REPORTS/.approvals"
}

field() { jq -r ".$1" <<<"$output"; }

fake_ps() {  # $BATS_TEST_TMPDIR/bin/fakeps: this shell → 100 ($FAKE_COMM) → 101 ($FAKE_TERM, Terminal by default; its ucomm is $FAKE_TERM_UCOMM or the program's name) → 1
  stub fakeps 'while [ $# -gt 0 ]; do case "$1" in -o) o="$2"; shift 2 ;; -p) p="$2"; shift 2 ;; *) shift ;; esac; done
t="${FAKE_TERM:-/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal}"
case "$o:$p" in
  ppid=:100) echo 101 ;; ppid=:101) echo 1 ;; ppid=:*) echo 100 ;;
  comm=:101|args=:101) echo "$t" ;;
  ucomm=:101) u="${FAKE_TERM_UCOMM:-${t##*/}}"; echo "${u:0:16}" ;;
  ucomm=:*) echo "${FAKE_COMM:-zsh}" ;;
  comm=:*) echo "${FAKE_COMM:-zsh}" ;;
  args=:*) echo "${FAKE_ARGS:-${FAKE_COMM:-zsh}}" ;;
esac'
}

# Signing test keys. Keys live in $BATS_TEST_TMPDIR; signing uses -c options, never a global config.
commit() {  # REPO — commit everything git doesn't ignore
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=owner@example.com -c commit.gpgsign=false commit -q --allow-empty -m c
}

# A file's signed origin, built once in setup_file (release_tree, in a throwaway HOME) and copied into each test as
# $O, with the key that signed it, so a test can change its copy or sign more releases.
signed_origin() {  # PATH...
  ( export HOME="$BATS_FILE_TMPDIR/build/home" BATS_TEST_TMPDIR="$BATS_FILE_TMPDIR/build"
    unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM; mkdir -p "$HOME"
    release_tree "$BATS_TEST_TMPDIR/origin" "$@" )
}
copy_signed_origin() {
  cp -R "$BATS_FILE_TMPDIR/build/origin" "$BATS_FILE_TMPDIR/build/keys" "$BATS_TEST_TMPDIR/"
  O="$BATS_TEST_TMPDIR/origin"
}
