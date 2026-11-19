#!/bin/bash
# Installs devward: a git checkout of one signed release, in ~/.local/share/devward.
#
# Don't pipe it into a shell. Download it, compare its SHA-256 with the one in the README, then run it:
#   curl -fsSLO https://raw.githubusercontent.com/b0dea/devward/main/install.sh
#   shasum -a 256 install.sh
#   bash install.sh
#
# It trusts one thing: the release tag and commit pinned below. It refuses a clone whose tag isn't exactly that commit,
# or whose tag isn't signed by a key in that commit's own .github/allowed_signers. Updates after that go through
# devward update, which takes only releases those signers vouch for. The Homebrew formula runs this same script with
# its own pins and --no-link.
#
# Usage: bash install.sh [--tag vX.Y.Z --commit SHA] [--no-link]   Exit: 0 installed, 1 refused, 2 usage.

# Filled in when a release is published: ci/release-pins.sh prints both.
PIN_TAG=""
PIN_COMMIT=""

# Where to clone from. Another place (a mirror, the tests) changes nothing about trust: the pinned commit decides.
URL="${DEVWARD_INSTALL_URL:-https://github.com/b0dea/devward.git}"
DEST="$HOME/.local/share/devward"

stop() { echo "devward install: $1" >&2; exit 1; }
usage() { echo "usage: bash install.sh [--tag vX.Y.Z --commit SHA] [--no-link]" >&2; exit 2; }

tag="$PIN_TAG"; commit="$PIN_COMMIT"; link=1
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) [ $# -ge 2 ] || usage; tag="$2"; shift 2 ;;
    --commit) [ $# -ge 2 ] || usage; commit="$2"; shift 2 ;;
    --no-link) link=""; shift ;;
    *) usage ;;
  esac
done
[ -n "$tag$commit" ] || stop "no release is pinned in this installer. Download it again from the README at https://github.com/b0dea/devward."
printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || stop "the pinned release must be a tag such as v1.2.3, not $tag."
printf '%s\n' "$commit" | grep -Eq '^[0-9a-f]{40}$' || stop "the pinned commit must be a full 40-character SHA, not $commit."

# The floor: macOS 15 ships jq, which devward needs; git needs Apple's Command Line Tools.
os="$(sw_vers -productVersion 2>/dev/null)"
case "${os%%.*}" in ''|*[!0-9]*) stop "could not read the macOS version (devward runs on macOS only)." ;; esac
[ "${os%%.*}" -ge 15 ] || stop "devward needs macOS 15 or later; this Mac has macOS $os."
xcode-select -p >/dev/null 2>&1 \
  || stop "devward needs Apple's Command Line Tools, which include git. Install them by typing: xcode-select --install
Then run this installer again."

[ ! -e "$DEST" ] && [ ! -L "$DEST" ] \
  || stop "$DEST already exists. To update it, type: devward update. To start over: devward uninstall, delete that folder, then run this again."
mkdir -p "${DEST%/*}" || stop "could not make ${DEST%/*}."
tmp="$(mktemp -d "${DEST%/*}/.devward-install.XXXXXX")" || stop "could not make a temporary folder in ${DEST%/*}."
trap 'rm -rf "$tmp"' EXIT
r="$tmp/devward"
# No hooks, fsmonitor or replace refs from the clone itself, before or after it is verified.
g() { git --no-replace-objects -C "$r" -c core.fsmonitor= -c core.hooksPath=/dev/null "$@"; }

echo "Cloning devward $tag from $URL"
# --no-local: a clone from a folder would otherwise copy its objects unchecked, so a tree or file stored under the
# pinned commit's ids could differ from it. An empty template: no hooks from the person's init.templateDir.
mkdir "$tmp/template" || stop "could not make a temporary folder in $tmp."
git -c core.hooksPath=/dev/null -c advice.detachedHead=false clone --quiet --no-local --template="$tmp/template" \
  --branch "$tag" -- "$URL" "$r" \
  || stop "could not clone $tag from $URL (git's message is above). Nothing was installed."
head="$(g rev-parse -q --verify 'HEAD^{commit}')"
tagged="$(g rev-parse -q --verify "refs/tags/$tag^{commit}")"
[ "$head" = "$commit" ] && [ "$tagged" = "$commit" ] \
  || stop "$tag on $URL is commit ${tagged:-unknown}, not the pinned $commit: refusing it. Nothing was installed."

# Only now, with the content pinned, does any of the clone's code run: the repo's own release checks, the ones session
# start and the fixes make, so a copy they would refuse is refused now.
. "$r/checks/lib/repo.sh" || stop "the release has no checks/lib/repo.sh. Nothing was installed."
devward_verify_clone "$r" "$tag" "$commit" || stop "$DEVWARD_CLONE_PROBLEM: refusing it. Nothing was installed."

# Checked again: another install may have finished while this one cloned. rename(2), unlike mv, never moves the
# clone into a folder that appeared there since, and fails unless that folder is empty.
[ ! -e "$DEST" ] && [ ! -L "$DEST" ] || stop "$DEST appeared while this installer was cloning: another install got there first. Nothing was installed."
/usr/bin/perl -e 'rename($ARGV[0], $ARGV[1]) or die "$!\n"' "$r" "$DEST" || stop "could not move the clone to $DEST."
# The first trusted signers and the highest release this Mac has run, as session start and devward update read them.
if old="$(devward_downgrade_from "$tag")"; then
  echo "WARNING: $tag is older than $old, which this Mac ran before. Type devward update to move to the newest release."
else
  devward_note_release "$tag" "$DEST" || stop "installed in $DEST, but could not record $tag as trusted in ~/.config/devward."
fi
echo "Installed devward $tag (commit $commit) in $DEST."

cmd="devward"
if [ -n "$link" ]; then
  if [ -d "$HOME/.local/bin" ] && [ ! -e "$HOME/.local/bin/devward" ] && [ ! -L "$HOME/.local/bin/devward" ]; then
    ln -s "$DEST/bin/devward" "$HOME/.local/bin/devward" || stop "could not link $HOME/.local/bin/devward."
    echo "Linked $HOME/.local/bin/devward to it."
  else
    cmd="$DEST/bin/devward"
    echo "To type devward from any folder, add this line to ~/.zshrc, then open a new Terminal window:"
    echo '  export PATH="$HOME/.local/share/devward/bin:$PATH"'
  fi
fi
echo "Next: type $cmd agent. It starts your coding agent in the devward folder; then type /posture."
