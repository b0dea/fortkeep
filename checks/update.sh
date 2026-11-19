#!/bin/bash
# Moves this copy to the newest release: a version tag (v1.2.3) signed by a maintainer. Use it instead of
# `git pull`, which takes whatever is on main. A release is checked against the signers this copy lists before
# the move (.github/allowed_signers), so only a maintainer already trusted here can release, or name a new one.
# The person runs it in the Terminal app.
SELF="$(cd "$(dirname "$0")/.." && pwd)"
. "$SELF/checks/lib/repo.sh"
R="${DEVWARD_REPO:-$SELF}"
stop() { echo "Not updated: $1" >&2; exit 1; }
# Checked before anything else is sourced: a copy with local changes, or with files and git settings that run
# commands on a checkout, isn't moved (its signers list or hooks could have been edited).
devward_local_changes "$R" && stop "tracked files in $R have local changes. Don't run fixes; reinstall a signed release unless you made these changes yourself."
extras="$(devward_config_extras "$R")"
[ -z "$extras" ] || stop "this copy has files or git settings that change what runs here ($(printf '%s' "$extras" | paste -sd, - | sed 's/,/, /g')). Reinstall a signed release."
# Only from where the first verified install fetched (devward_note_release records it). The address isn't printed:
# it can carry a token.
origin="$(devward_origin_url "$R")" || stop "this copy's git settings must name exactly one place to fetch releases from (remote.origin.url)."
recorded="$(devward_origin_file)" || stop "could not read your home folder from your account."
if [ -s "$recorded" ] && [ "$(head -n 1 "$recorded")" != "$origin" ]; then
  stop "this copy now fetches from another place than the one this Mac recorded at its first install (~/.config/devward/origin). Reinstall a signed release from GitHub."
fi
# git would fetch from another place than remote.origin.url names, so the recorded place would no longer hold.
if devward_origin_rewritten "$R" "$origin"; then
  stop "a url.<...>.insteadOf or pushInsteadOf git setting, in this copy or in your own git config, changes where this copy fetches from. Remove it, then run checks/update.sh again."
fi
. "$SELF/checks/lib/common.sh"
# The copy's own git config could still name a hook folder or a transport that runs a command: none is used.
# The releases are public, so no credential helper or password prompt is needed either.
git_() {
  GIT_TERMINAL_PROMPT=0 devward_git "$R" -c core.hooksPath=/dev/null -c protocol.allow=never -c protocol.https.allow=always \
    -c protocol.ssh.allow=always -c remote.origin.uploadpack=git-upload-pack -c credential.helper= \
    -c core.askPass=/usr/bin/false "$@"
}
on_branch() { git_ symbolic-ref -q HEAD >/dev/null; }
# --force: a tag moved on GitHub replaces the local one instead of failing the fetch; it still has to verify.
git_ fetch --quiet --tags --force origin || stop "could not fetch the releases (git's message is above)."

# One step: to the newest release this copy's signers vouch for. Repeated, because a release may change the
# signers the next one is checked against. The first step trusts the signers this Mac recorded (devward_signers_to),
# each later one those of the release it just moved to; never the working tree.
signers="$(mktemp "${TMPDIR:-/tmp}/devward-signers.XXXXXX")" || stop "could not make a temporary file."
trap 'rm -f "$signers"' EXIT
moved=""
while :; do
  head="$(git_ rev-parse HEAD)" || stop "could not read this copy's current commit."
  if [ -z "$moved" ]; then devward_signers_to "$R" "$head" "$signers" || stop "could not read the signers this Mac trusts."
  else git_ cat-file blob "$head:.github/allowed_signers" > "$signers" 2>/dev/null || : > "$signers"; fi
  new=""; current=""; ignored=""
  for t in $(devward_releases "$R"); do
    devward_release_signed "$R" "$t" "$signers" || { ignored="$ignored $t"; continue; }
    to="$(git_ rev-parse -q --verify "refs/tags/$t^{commit}")" || stop "could not read $t."
    # A copy still on a branch moves to the newest release, wherever that is. One that already follows releases
    # only moves forward: an older release, or one from another line of history, is passed over.
    if on_branch; then new="$t"; break; fi
    if [ "$to" = "$head" ]; then current="$t"; break; fi
    if git_ merge-base --is-ancestor "$head" "$to"; then new="$t"; break; fi
  done
  [ -n "$new" ] || break
  git_ checkout --quiet --detach "$to" || stop "could not check out $new."
  moved="$new"
done
[ -z "$ignored" ] || echo "Ignored, not a release signed by a listed maintainer:$ignored. Tell a maintainer." >&2
if [ -n "$moved" ]; then
  devward_note_release "$moved" "$R" || :
  echo "Updated to $moved. Close your coding agent and start it again in this folder, so it loads this version."
elif [ -n "$current" ]; then devward_note_release "$current" "$R" || :; echo "Already on the newest release, $current."
elif on_branch; then stop "found no release signed by a maintainer this copy lists in .github/allowed_signers."
else echo "No newer release signed by a maintainer this copy lists."; fi
