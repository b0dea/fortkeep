#!/bin/bash
# Prints what a published release pins: its commit and the SHA-256 of the tarball GitHub serves for it, as the lines to
# paste into install.sh, packaging/homebrew/fortkeep.rb and the README. Run it after the tag is pushed; the release
# workflow runs it too, for the release notes. Read-only, apart from the download.
# Usage: ci/release-pins.sh v1.2.3   Exit: 0 printed, 1 refused, 2 usage.
. "$(dirname "$0")/../checks/lib/common.sh"
. "$(dirname "$0")/../checks/lib/repo.sh"
v="${1:-}"
stop() { echo "release-pins: $1" >&2; exit 1; }
fortkeep_is_version "$v" || { echo "usage: ci/release-pins.sh v1.2.3" >&2; exit 2; }
c="$(fortkeep_git "$FORTKEEP_REPO" rev-parse -q --verify "refs/tags/$v^{commit}")" || stop "no tag $v here: git fetch --tags first"
tmp="$(mktemp -d)" || stop "could not make a temporary folder"
trap 'rm -rf "$tmp"' EXIT
# The same check a new install makes, on a clone made the way install.sh makes it: the tag is the commit, signed by a
# key in that commit's own signers list, and nothing fortkeep would count as a local change.
mkdir "$tmp/template" || stop "could not make a temporary folder in $tmp"
git -c core.hooksPath=/dev/null -c advice.detachedHead=false clone --quiet --no-local --template="$tmp/template" \
  --branch "$v" -- "$FORTKEEP_REPO" "$tmp/clone" || stop "could not clone $v from $FORTKEEP_REPO (git's message is above)"
fortkeep_verify_clone "$tmp/clone" "$v" "$c" || stop "$FORTKEEP_CLONE_PROBLEM, so a new install would refuse it"

url="https://github.com/$FORTKEEP_RELEASE_NAME/archive/refs/tags/$v.tar.gz"
curl -fsSL --proto '=https' "$url" -o "$tmp/release.tar.gz" || stop "could not download $url (is the tag pushed?)"
tarsha="$(shasum -a 256 < "$tmp/release.tar.gz" | cut -d' ' -f1)"

# install.sh as it will be once the two pin lines are pasted in, for the SHA-256 the README shows.
pin_tag="PIN_TAG=\"$v\""; pin_commit="PIN_COMMIT=\"$c\""
for p in PIN_TAG PIN_COMMIT; do
  [ "$(grep -c "^$p=" "$FORTKEEP_REPO/install.sh")" -eq 1 ] || stop "install.sh must have exactly one $p= line"
done
awk -v t="$pin_tag" -v k="$pin_commit" '/^PIN_TAG=/ { print t; next } /^PIN_COMMIT=/ { print k; next } { print }' \
  "$FORTKEEP_REPO/install.sh" > "$tmp/install.sh" || stop "could not render install.sh"
instsha="$(shasum -a 256 < "$tmp/install.sh" | cut -d' ' -f1)"

cat <<EOF
fortkeep $v
  commit          $c
  tarball         $url
  tarball sha256  $tarsha

install.sh, the two pin lines:
  $pin_tag
  $pin_commit

packaging/homebrew/fortkeep.rb:
  url "$url"
  sha256 "$tarsha"
  COMMIT = "$c"

README.md, the installer's SHA-256 once those two lines are in install.sh:
  $instsha
EOF
