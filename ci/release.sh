#!/bin/bash
# make release: signs a release tag on main's tip and keeps it only if checks/update.sh would accept it.
# Publishing the tag is a separate step. Usage: ci/release.sh v1.2.3   Exit: 0 tagged, 1 refused.
. "$(dirname "$0")/../checks/lib/common.sh"
. "$(dirname "$0")/../checks/lib/repo.sh"
v="${1:-}"
stop() { echo "release: $1" >&2; exit 1; }
[[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || stop "usage: make release VERSION=v1.2.3"
[ "$(devward_git "$DEVWARD_REPO" symbolic-ref --short -q HEAD)" = main ] || stop "releases are tagged on main"
# A maintainer runs this on main in development mode, which devward_release_gate lets through, so the checks are
# made here directly: no local changes, and no file or git setting beyond the tracked files that changes what agents
# load or what git runs. Git hooks are left out, since make install puts lefthook's there: the tag is made and removed
# with no hook folder at all, so none runs (reference-transaction would, on every ref change).
devward_local_changes "$DEVWARD_REPO" && stop "tracked files have local changes"
extras="$(devward_config_extras "$DEVWARD_REPO" | grep -v '^git hook ')"
[ -z "$extras" ] || stop "this copy has files or git settings beyond its tracked files: $(printf '%s' "$extras" | paste -sd, - | sed 's/,/, /g')"
prev="$(devward_releases "$DEVWARD_REPO" | head -n 1)"
tag_() { devward_git "$DEVWARD_REPO" -c core.hooksPath=/dev/null tag "$@"; }
tag_ -s -m "$DEVWARD_RELEASE_NAME $v" "$v" || stop "could not sign the tag; teach/GD-GT-01.md sets up a signing key"
accepted() {  # a fresh clone checks the release against main's signers, a copy on the last release against that one's
  local old rc
  devward_release_signed "$DEVWARD_REPO" "$v" "$DEVWARD_REPO/.github/allowed_signers" || return 1
  [ -n "$prev" ] || return 0
  old="$(mktemp)" || return 1
  devward_git "$DEVWARD_REPO" show "refs/tags/$prev:.github/allowed_signers" > "$old" 2>/dev/null && devward_release_signed "$DEVWARD_REPO" "$v" "$old"; rc=$?
  rm -f "$old"; return "$rc"
}
if ! accepted; then
  tag_ -d "$v" >/dev/null || stop "copies would refuse $v, and the tag could not be removed: delete it before you push"
  stop "your SSH signing key must be in .github/allowed_signers${prev:+, both on main and in $prev}, or copies would refuse $v; the tag was removed"
fi
echo "Tagged $v. Publish it when you're ready: git push origin main $v"
